import Foundation

public struct ExtraFile: Sendable, Equatable {
    public var path: String
    public var text: String
    public init(path: String, text: String) { self.path = path; self.text = text }
}

public struct CompletionRequest: Sendable, Equatable {
    public var path: String
    public var prefix: String
    public var suffix: String
    public var extras: [ExtraFile]
    public var maxTokens: Int

    public init(path: String, prefix: String, suffix: String, extras: [ExtraFile], maxTokens: Int) {
        self.path = path
        self.prefix = prefix
        self.suffix = suffix
        self.extras = extras
        self.maxTokens = maxTokens
    }
}

public enum ProviderError: Error, Equatable, CustomStringConvertible {
    case badURL(String)
    case http(status: Int, body: String)
    case badResponse(String)

    public var description: String {
        switch self {
        case .badURL(let url): return "bad URL: \(url)"
        case .http(let status, let body): return "HTTP \(status): \(body.prefix(300))"
        case .badResponse(let body): return "unexpected response: \(body.prefix(300))"
        }
    }
}

/// Providers never retry; cancellation comes from the calling Task.
public protocol CompletionProvider: Sendable {
    func complete(_ request: CompletionRequest) async throws -> String
}

let fimStopStrings = ["<|file_sep|>", "<|fim_prefix|>", "<|fim_suffix|>", "<|fim_middle|>", "<|repo_name|>", "<|endoftext|>"]

struct JSONPoster: Sendable {
    var session: URLSession
    var timeout: TimeInterval
    var apiKey: String?

    func post(_ url: URL, body: JSONValue) async throws -> JSONValue {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try body.encoded()
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ProviderError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        do { return try JSONValue.decode(data) }
        catch { throw ProviderError.badResponse(String(decoding: data, as: UTF8.self)) }
    }
}

func endpoint(_ base: String, _ path: String) throws -> URL {
    var trimmed = base
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    // /infill lives at the server root, not under /v1.
    if path == "/infill", trimmed.hasSuffix("/v1") { trimmed.removeLast(3) }
    if path.hasPrefix("/v1/"), trimmed.hasSuffix("/v1") { trimmed.removeLast(3) }
    guard let url = URL(string: trimmed + path), url.scheme != nil else { throw ProviderError.badURL(base) }
    return url
}

public struct LlamaInfillProvider: CompletionProvider {
    public var config: Config
    var poster: JSONPoster

    public init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.poster = JSONPoster(session: session, timeout: Double(config.timeoutMs) / 1000, apiKey: config.apiKey)
    }

    public func body(for request: CompletionRequest) -> JSONValue {
        [
            "model": .string(config.model),
            "input_prefix": .string(request.prefix),
            "input_suffix": .string(request.suffix),
            "input_extra": .array(request.extras.map { ["filename": .string($0.path), "text": .string($0.text)] }),
            "n_predict": .int(request.maxTokens),
            "temperature": 0,
            "top_k": 20,
            "cache_prompt": true,
            "stream": false,
            "stop": .array(fimStopStrings.map { .string($0) }),
        ]
    }

    public func complete(_ request: CompletionRequest) async throws -> String {
        let reply = try await poster.post(try endpoint(config.baseURL, "/infill"), body: body(for: request))
        guard let content = reply["content"]?.stringValue else {
            throw ProviderError.badResponse(String(decoding: (try? reply.encoded()) ?? Data(), as: UTF8.self))
        }
        return content
    }
}

public struct OpenAIFIMProvider: CompletionProvider {
    public var config: Config
    var poster: JSONPoster

    public init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.poster = JSONPoster(session: session, timeout: Double(config.timeoutMs) / 1000, apiKey: config.apiKey)
    }

    /// Qwen Coder repo-level FIM format.
    public static func prompt(for request: CompletionRequest, repoName: String = "project") -> String {
        var prompt = "<|repo_name|>\(repoName)\n"
        for extra in request.extras {
            prompt += "<|file_sep|>\(extra.path)\n\(extra.text)"
            if !extra.text.hasSuffix("\n") { prompt += "\n" }
        }
        prompt += "<|file_sep|>\(request.path)\n<|fim_prefix|>\(request.prefix)<|fim_suffix|>\(request.suffix)<|fim_middle|>"
        return prompt
    }

    public func body(for request: CompletionRequest) -> JSONValue {
        [
            "model": .string(config.model),
            "prompt": .string(Self.prompt(for: request)),
            "max_tokens": .int(request.maxTokens),
            "temperature": 0,
            "stream": false,
            "stop": .array(fimStopStrings.map { .string($0) }),
        ]
    }

    public func complete(_ request: CompletionRequest) async throws -> String {
        let reply = try await poster.post(try endpoint(config.baseURL, "/v1/completions"), body: body(for: request))
        guard let text = reply["choices"]?.arrayValue?.first?["text"]?.stringValue else {
            throw ProviderError.badResponse(String(decoding: (try? reply.encoded()) ?? Data(), as: UTF8.self))
        }
        return text
    }
}

public func makeProvider(_ config: Config, session: URLSession = .shared) -> any CompletionProvider {
    switch config.provider {
    case .llamaInfill: return LlamaInfillProvider(config: config, session: session)
    case .openAIFIM: return OpenAIFIMProvider(config: config, session: session)
    }
}
