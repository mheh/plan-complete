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
    var folderConfig: Config {
        var config = Config()
        config.guide = "docs/guide"
        return config
    }

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
        try "{}".write(to: root.appendingPathComponent(".plan-complete.json"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func requestHoldsGuideAndScope() async throws {
        let root = try makeRoot()
        let provider = RecordingProvider(reply: "capacity: 10)")
        let engine = Engine(root: root, config: folderConfig, provider: provider)
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
        let engine = Engine(root: root, config: folderConfig, provider: provider)
        let doc = TextDocument(path: root.appendingPathComponent("a.swift").path, text: "struct A {\n    func f() {\n        g(\n    }\n}")
        let lsp = ExtraFile(path: "a.swift.signature", text: "g(count: Int)")
        _ = try await engine.complete(document: doc, line: 2, utf16Column: 10, editorContext: [lsp])
        #expect(provider.requests.first?.extras.map(\.path) == ["a.swift.signature"])
    }

    @Test func cacheAndTypeahead() async throws {
        let root = try makeRoot()
        let provider = RecordingProvider(reply: "return a + b")
        let engine = Engine(root: root, config: folderConfig, provider: provider)
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

@Suite struct PlanFileTests {
    func makeRoot(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pc-\(UUID().uuidString)")
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func plainPlanIsTheDefault() async throws {
        let root = try makeRoot([
            ".plan-complete.json": "{}",
            "PLAN.md": """
            # Cache work

            ## Step 1: ResponseCache
            Edit `Sources/Net/Cache.swift`. `actor ResponseCache` holds at most 100 items.

            ### Eviction
            `private func evictIfNeeded()` drops the oldest key.

            ## Step 2: UI
            Add a `CacheView` in `Sources/UI/CacheView.swift`.
            """,
        ])
        let provider = RecordingProvider(reply: "x")
        let engine = Engine(root: root, config: Config(), provider: provider)
        let doc = TextDocument(path: root.appendingPathComponent("Sources/Net/Cache.swift").path, text: "actor ResponseCache {\n    \n}")
        let result = try await engine.complete(document: doc, line: 1, utf16Column: 4)
        #expect(result.sources.first == "PLAN.md#Step 1: ResponseCache")
        #expect(!result.sources.contains("PLAN.md#Step 2: UI"))
        #expect(await engine.guide().map(\.heading).contains("Eviction"))
    }

    @Test func guideFolder() async throws {
        let root = try makeRoot([".plan-complete.json": "{}", "notes/a.md": "## A\nalpha", "notes/sub/b.md": "## B\nbeta"])
        var config = Config()
        config.guide = "notes"
        let engine = Engine(root: root, config: config, provider: RecordingProvider(reply: ""))
        #expect(await engine.guide().map(\.source) == ["notes/a.md", "notes/sub/b.md"])
    }

    @Test func globalThenRepoConfig() throws {
        let root = try makeRoot([
            "global.json": #"{"baseURL": "http://gpu:8090", "model": "m1"}"#,
            ".plan-complete.json": #"{"model": "m2"}"#,
        ])
        let config = try Config.load(root: root, globalFile: root.appendingPathComponent("global.json"))
        #expect(config.baseURL == "http://gpu:8090")
        #expect(config.model == "m2")
        #expect(config.guide == "PLAN.md")
    }

    @Test func oversizedSectionIsCut() {
        let chunk = GuideChunk(source: "PLAN.md", heading: "Big", files: [], symbols: [], priority: 0,
                               text: "Sources/A.swift " + String(repeating: "word ", count: 2000))
        let picked = GuideSelector(budget: 100).select(chunks: [chunk], path: "Sources/A.swift", window: "")
        #expect(picked.first?.text.count == 400)
    }
}

@Suite struct PlanRuleTests {
    func makeRoot(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    func load(_ root: URL, global: String? = nil) throws -> Config {
        var globalFile: URL?
        if let global {
            globalFile = root.appendingPathComponent("global.json")
            try global.write(to: globalFile!, atomically: true, encoding: .utf8)
        }
        return try Config.load(root: root, globalFile: globalFile)
    }

    @Test func emptyRepoFileMeansPlanFileOnly() throws {
        let root = try makeRoot([".plan-complete.json": "{}"])
        #expect(try load(root).guide == "PLAN.md")
        #expect(try load(root, global: "{}").guide == "PLAN.md")
    }

    @Test func onlyTheRepoFileNamesThePlan() throws {
        let root = try makeRoot([".plan-complete.json": #"{"model": "x"}"#])
        #expect(try load(root, global: #"{"guide": "docs"}"#).guide == "PLAN.md")
        let editor = try load(root).applyingEditor(["guide": "docs", "maxTokens": 9])
        #expect(editor.guide == "PLAN.md")
        #expect(editor.maxTokens == 9)
        let named = try makeRoot([".plan-complete.json": #"{"guide": "docs/plan"}"#])
        #expect(try load(named).guide == "docs/plan")
    }

    @Test func unsafeGuideFallsBack() {
        for bad in ["/etc", "../other", "a/../../b", "~/x", "", "  ", #"C:\plans"#, "c:/plans", #"\\server\share"#, #"..\other"#] {
            #expect(Config.safeGuide(bad) == "PLAN.md", "\(bad)")
        }
        #expect(Config.safeGuide("docs/plan") == "docs/plan")
        #expect(Config.safeGuide(#"docs\plan"#) == "docs/plan")
    }

    @Test func relativePathUsesForwardSlashes() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pc-rel", isDirectory: true)
        #expect(relativePath(of: root.appendingPathComponent("Sources/Net/Cache.swift"), to: root) == "Sources/Net/Cache.swift")
        #expect(relativePath(of: root.appendingPathComponent("a.swift"), to: root.appendingPathComponent("a.swift")) != "")
    }

    @Test func states() throws {
        #expect(PlanState.check(root: try makeRoot(["PLAN.md": "x"]), guide: "PLAN.md") == .noConfig)
        #expect(PlanState.check(root: try makeRoot([".plan-complete.json": "{}"]), guide: "PLAN.md") == .noPlan(guide: "PLAN.md"))
        let on = try makeRoot([".plan-complete.json": "{}", "PLAN.md": "x"])
        #expect(PlanState.check(root: on, guide: "PLAN.md") == .on(guide: "PLAN.md"))
        #expect(PlanState.check(root: on, guide: "PLAN.md", enabled: false) == .disabled)
        let emptyFolder = try makeRoot([".plan-complete.json": "{}", "docs/plan/readme.txt": "x"])
        #expect(PlanState.check(root: emptyFolder, guide: "docs/plan") == .noPlan(guide: "docs/plan"))
        let folder = try makeRoot([".plan-complete.json": "{}", "docs/plan/a.md": "x"])
        #expect(PlanState.check(root: folder, guide: "docs/plan") == .on(guide: "docs/plan"))
    }

    @Test func offReturnsEarlyWithNoModelCall() async throws {
        let root = try makeRoot(["PLAN.md": "## Step\nx"])
        let provider = RecordingProvider(reply: "never")
        let engine = Engine(root: root, config: Config(), provider: provider)
        let doc = TextDocument(path: root.appendingPathComponent("a.swift").path, text: "let a = ")
        #expect(try await engine.complete(document: doc, line: 0, utf16Column: 8).text == "")
        #expect(provider.requests.isEmpty)
        await engine.setBypassPlanRule(true)
        #expect(try await engine.complete(document: doc, line: 0, utf16Column: 8).text == "never")
    }

    @Test func toggleOff() async throws {
        let root = try makeRoot([".plan-complete.json": "{}", "PLAN.md": "## Step\nx"])
        let provider = RecordingProvider(reply: "y")
        let engine = Engine(root: root, config: Config(), provider: provider)
        await engine.setEnabled(false)
        let doc = TextDocument(path: root.appendingPathComponent("a.swift").path, text: "let a = ")
        #expect(try await engine.complete(document: doc, line: 0, utf16Column: 8).text == "")
        await engine.setEnabled(true)
        #expect(try await engine.complete(document: doc, line: 0, utf16Column: 8).text == "y")
    }
}
