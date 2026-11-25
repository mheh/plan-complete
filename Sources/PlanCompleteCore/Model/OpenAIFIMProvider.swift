import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
