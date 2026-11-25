import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
            "n_indent": .int(Self.indent(ofLastLine: request.prefix)),
            "temperature": 0,
            "top_k": 20,
            "cache_prompt": true,
            "stream": false,
            "stop": .array(fimStopStrings.map { .string($0) }),
        ]
    }

    /// With `n_indent` the server ends the completion at the first line that is indented less,
    /// so the model does not write on to `n_predict` for the cleanup to cut.
    static func indent(ofLastLine prefix: String) -> Int {
        let line = prefix.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        return line.prefix { $0 == " " || $0 == "\t" }.count
    }

    public func complete(_ request: CompletionRequest) async throws -> String {
        let reply = try await poster.post(try endpoint(config.baseURL, "/infill"), body: body(for: request))
        guard let content = reply["content"]?.stringValue else {
            throw ProviderError.badResponse(String(decoding: (try? reply.encoded()) ?? Data(), as: UTF8.self))
        }
        return content
    }
}
