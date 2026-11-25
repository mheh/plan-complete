import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

public func makeProvider(_ config: Config, session: URLSession = .shared) -> any CompletionProvider {
    switch config.provider {
    case .llamaInfill: return LlamaInfillProvider(config: config, session: session)
    case .openAIFIM: return OpenAIFIMProvider(config: config, session: session)
    }
}
