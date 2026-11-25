import Foundation
import Testing
@testable import PlanCompleteCore

@Suite struct PlanRuleTests {
    func load(_ root: URL, global: String? = nil) throws -> Config {
        var globalFile: URL?
        if let global {
            globalFile = root.appendingPathComponent("global.json")
            try global.write(to: globalFile!, atomically: true, encoding: .utf8)
        }
        return try Config.load(root: root, globalFile: globalFile)
    }

    @Test func emptyRepoFileMeansPlanFileOnly() throws {
        let root = try makeRepo([".plan-complete.json": "{}"])
        #expect(try load(root).guide == "PLAN.md")
        #expect(try load(root, global: "{}").guide == "PLAN.md")
    }

    @Test func onlyTheRepoFileNamesThePlan() throws {
        let root = try makeRepo([".plan-complete.json": #"{"model": "x"}"#])
        #expect(try load(root, global: #"{"guide": "docs"}"#).guide == "PLAN.md")
        let editor = try load(root).applyingEditor(["guide": "docs", "maxTokens": 9])
        #expect(editor.guide == "PLAN.md")
        #expect(editor.maxTokens == 9)
        let named = try makeRepo([".plan-complete.json": #"{"guide": "docs/plan"}"#])
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
        #expect(PlanState.check(root: try makeRepo(["PLAN.md": "x"]), guide: "PLAN.md") == .noConfig)
        #expect(PlanState.check(root: try makeRepo([".plan-complete.json": "{}"]), guide: "PLAN.md") == .noPlan(guide: "PLAN.md"))
        let on = try makeRepo([".plan-complete.json": "{}", "PLAN.md": "x"])
        #expect(PlanState.check(root: on, guide: "PLAN.md") == .on(guide: "PLAN.md"))
        #expect(PlanState.check(root: on, guide: "PLAN.md", enabled: false) == .disabled)
        let emptyFolder = try makeRepo([".plan-complete.json": "{}", "docs/plan/readme.txt": "x"])
        #expect(PlanState.check(root: emptyFolder, guide: "docs/plan") == .noPlan(guide: "docs/plan"))
        let folder = try makeRepo([".plan-complete.json": "{}", "docs/plan/a.md": "x"])
        #expect(PlanState.check(root: folder, guide: "docs/plan") == .on(guide: "docs/plan"))
    }

    @Test func offReturnsEarlyWithNoModelCall() async throws {
        let root = try makeRepo(["PLAN.md": "## Step\nx"])
        let provider = RecordingProvider(reply: "never")
        let engine = Engine(root: root, config: Config(), provider: provider)
        let doc = TextDocument(path: root.appendingPathComponent("a.swift").path, text: "let a = ")
        #expect(try await engine.complete(document: doc, line: 0, utf16Column: 8).text == "")
        #expect(await provider.requests.isEmpty)
        await engine.setBypassPlanRule(true)
        #expect(try await engine.complete(document: doc, line: 0, utf16Column: 8).text == "never")
    }

    @Test func toggleOff() async throws {
        let root = try makeRepo([".plan-complete.json": "{}", "PLAN.md": "## Step\nx"])
        let provider = RecordingProvider(reply: "y")
        let engine = Engine(root: root, config: Config(), provider: provider)
        await engine.setEnabled(false)
        let doc = TextDocument(path: root.appendingPathComponent("a.swift").path, text: "let a = ")
        #expect(try await engine.complete(document: doc, line: 0, utf16Column: 8).text == "")
        await engine.setEnabled(true)
        #expect(try await engine.complete(document: doc, line: 0, utf16Column: 8).text == "y")
    }
}
