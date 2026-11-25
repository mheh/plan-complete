import Foundation
import Testing
@testable import PlanCompleteCore

@Suite struct PlanFileTests {
    @Test func plainPlanIsTheDefault() async throws {
        let root = try makeRepo([
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
        let root = try makeRepo([".plan-complete.json": "{}", "notes/a.md": "## A\nalpha", "notes/sub/b.md": "## B\nbeta"])
        var config = Config()
        config.guide = "notes"
        let engine = Engine(root: root, config: config, provider: RecordingProvider(reply: ""))
        #expect(await engine.guide().map(\.source) == ["notes/a.md", "notes/sub/b.md"])
    }

    @Test func globalThenRepoConfig() throws {
        let root = try makeRepo([
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
