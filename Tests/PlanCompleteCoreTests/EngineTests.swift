import Foundation
import Testing
@testable import PlanCompleteCore

final class RecordingProvider: CompletionProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [CompletionRequest] = []
    let reply: String
    init(reply: String) { self.reply = reply }
    var requests: [CompletionRequest] { lock.withLock { _requests } }
    func complete(_ request: CompletionRequest) async throws -> String {
        lock.withLock { _requests.append(request) }
        return reply
    }
}

@Suite struct EngineTests {
    func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pc-\(UUID().uuidString)")
        let guide = root.appendingPathComponent("docs/guide")
        try FileManager.default.createDirectory(at: guide, withIntermediateDirectories: true)
        try """
        ---
        files: ["Sources/**"]
        symbols: [ResponseCache]
        ---
        ## Cache
        ResponseCache is an actor.
        """.write(to: guide.appendingPathComponent("cache.md"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func requestHoldsGuideAndScope() async throws {
        let root = try makeRoot()
        let provider = RecordingProvider(reply: "capacity: 10)")
        let engine = Engine(root: root, config: Config(), provider: provider)
        let path = root.appendingPathComponent("Sources/Cache.swift").path
        let doc = TextDocument(path: path, text: "actor ResponseCache {\n    init(capacity: Int) {}\n    convenience init() {\n        self.init(\n    }\n}")
        let result = try await engine.complete(document: doc, line: 3, utf16Column: 18)
        #expect(result.text == "capacity: 10)")
        let request = try #require(provider.requests.first)
        #expect(request.path == "Sources/Cache.swift")
        #expect(request.extras.map(\.path) == ["docs/guide/cache.md", "Sources/Cache.swift.scope"])
        #expect(result.sources.contains("docs/guide/cache.md#Cache"))
    }

    @Test func editorContextReplacesOwnScope() async throws {
        let root = try makeRoot()
        let provider = RecordingProvider(reply: "x")
        let engine = Engine(root: root, config: Config(), provider: provider)
        let doc = TextDocument(path: root.appendingPathComponent("a.swift").path, text: "struct A {\n    func f() {\n        g(\n    }\n}")
        let lsp = ExtraFile(path: "a.swift.signature", text: "g(count: Int)")
        _ = try await engine.complete(document: doc, line: 2, utf16Column: 10, editorContext: [lsp])
        #expect(provider.requests.first?.extras.map(\.path) == ["a.swift.signature"])
    }

    @Test func cacheAndTypeahead() async throws {
        let root = try makeRoot()
        let provider = RecordingProvider(reply: "return a + b")
        let engine = Engine(root: root, config: Config(), provider: provider)
        let path = root.appendingPathComponent("m.swift").path
        let doc = TextDocument(path: path, text: "func add() {\n    \n}")
        _ = try await engine.complete(document: doc, line: 1, utf16Column: 4)
        let again = try await engine.complete(document: doc, line: 1, utf16Column: 4)
        #expect(again.fromCache)
        let typed = TextDocument(path: path, text: "func add() {\n    ret\n}")
        let rest = try await engine.complete(document: typed, line: 1, utf16Column: 7)
        #expect(rest.text == "urn a + b")
        #expect(provider.requests.count == 1)
    }

    @Test func promptTemplate() {
        let request = CompletionRequest(path: "a.swift", prefix: "let ", suffix: "\n",
                                        extras: [ExtraFile(path: "g.md", text: "rule")], maxTokens: 8)
        #expect(OpenAIFIMProvider.prompt(for: request) ==
            "<|repo_name|>project\n<|file_sep|>g.md\nrule\n<|file_sep|>a.swift\n<|fim_prefix|>let <|fim_suffix|>\n<|fim_middle|>")
    }

    @Test func endpoints() throws {
        #expect(try endpoint("http://h:8090/v1/", "/infill").absoluteString == "http://h:8090/infill")
        #expect(try endpoint("http://h:8090", "/v1/completions").absoluteString == "http://h:8090/v1/completions")
        #expect(try endpoint("http://h:8090/v1", "/v1/completions").absoluteString == "http://h:8090/v1/completions")
    }

    @Test func configMerge() throws {
        let merged = try Config().merged(with: ["model": "other", "maxTokens": 10])
        #expect(merged.model == "other" && merged.maxTokens == 10 && merged.provider == .llamaInfill)
    }
}
