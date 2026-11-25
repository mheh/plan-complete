import Foundation
import Testing
@testable import PlanCompleteCore

@Suite struct ConfigTests {
    @Test func commentsAndTrailingCommas() throws {
        let text = """
        // a note
        {
          "model": "m", // the model
          /* block
             comment */
          "baseURL": "http://h:1/v1", "apiKey": "a // b /* c */",
          "context": { "signature": false, },
        }
        """
        let root = try makeRepo([".plan-complete.json": text])
        let config = try Config.load(root: root, globalFile: nil)
        #expect(config.model == "m")
        #expect(config.baseURL == "http://h:1/v1")
        #expect(config.apiKey == "a // b /* c */")
        #expect(config.context.signature == false)
    }

    @Test func nestedFieldsMergeOneByOne() throws {
        let root = try makeRepo([
            "global.json": #"{"context": {"timeoutMs": 50}, "scoring": {"file": 1}}"#,
            ".plan-complete.json": #"{"context": {"signature": false}}"#,
        ])
        let config = try Config.load(root: root, globalFile: root.appendingPathComponent("global.json"))
            .applyingEditor(["scoring": ["symbol": 9]])
        #expect(config.context == { var c = Config.Context(); c.timeoutMs = 50; c.signature = false; return c }())
        #expect(config.scoring.file == 1 && config.scoring.symbol == 9 && config.scoring.glob == 10)
    }

    @Test func unknownFieldsAreIgnored() throws {
        let config = try Config().merged(with: ["later": true, "context": ["hover": true]])
        #expect(config == Config())
    }

    @Test func templateIsTheDefaults() throws {
        let stripped = try JSONValue.decode(jsonc: Data(Setup.configTemplate.utf8))
        #expect(stripped == .object([:]))
        let uncommented = Setup.configTemplate.components(separatedBy: "\n")
            .map { $0.hasPrefix("  // \"") ? String($0.dropFirst(5)) : $0 }.joined(separator: "\n")
        let all = try JSONValue.decode(jsonc: Data(uncommented.utf8))
        #expect(try Config().merged(with: all) == Config())
        let fields = try JSONValue.decode(JSONEncoder().encode(Config())).objectValue ?? [:]
        #expect(Set(all.objectValue?.keys.map { $0 } ?? []) == Set(fields.keys).union(["apiKey"]))
    }

    @Test func scoringChangesTheRanking() {
        let named = GuideChunk(source: "PLAN.md", heading: "A", files: [], symbols: [], priority: 0, text: "about Cache.swift")
        let spans = GuideChunk(source: "PLAN.md", heading: "B", files: [], symbols: [], priority: 0, text: "`store` `evict` `items`")
        func first(_ scoring: Config.Scoring) -> String? {
            GuideSelector(budget: 100, scoring: scoring)
                .select(chunks: [spans, named], path: "Cache.swift", window: "store").first?.heading
        }
        #expect(first(.init()) == "A")
        var flat = Config.Scoring()
        flat.file = 1
        #expect(first(flat) == "B")
    }
}

@Suite struct SetupTests {
    @Test func enableWritesBothFilesOnce() throws {
        let root = try makeRepo()
        #expect(PlanState.check(root: root, guide: "PLAN.md") == .noConfig)
        #expect(try Setup.enable(root: root) == [".plan-complete.json", "PLAN.md"])
        #expect(PlanState.check(root: root, guide: "PLAN.md") == .on(guide: "PLAN.md"))
        #expect(try Setup.enable(root: root).isEmpty)
        #expect(try Config.load(root: root, globalFile: nil) == Config())
    }

    @Test func enableKeepsAnExistingPlan() throws {
        let root = try makeRepo(["PLAN.md": "## Mine\nx"])
        #expect(try Setup.enable(root: root) == [".plan-complete.json"])
        #expect(try String(contentsOf: root.appendingPathComponent("PLAN.md"), encoding: .utf8) == "## Mine\nx")
    }

    @Test func commentsInThePlanAreNotRead() {
        let chunks = Guide.parse(markdown: Setup.planTemplate, source: "PLAN.md")
        #expect(chunks.map(\.text) == ["# Plan"])
        #expect(Guide.parse(markdown: "## A\none <!-- note --> two\n<!-- open", source: "p").map(\.text) == ["## A\none  two"])
    }

    @Test func editorContextKeepsToItsBudget() {
        let extras = [ExtraFile(path: "a", text: String(repeating: "x", count: 30)), ExtraFile(path: "b", text: String(repeating: "y", count: 30)),
                      ExtraFile(path: "c", text: "z")]
        let kept = Engine.trimmed(extras, tokens: 10)
        #expect(kept.map(\.text.count) == [30, 10])
        #expect(Engine.trimmed(extras, tokens: 0).isEmpty)
    }

    @Test func failuresNameTheServer() {
        let config = Config()
        #expect(modelFailure(URLError(.cannotConnectToHost), config: config) == "no model server at http://127.0.0.1:8012")
        #expect(modelFailure(ProviderError.http(status: 404, body: ""), config: config) == "http://127.0.0.1:8012 has no /infill endpoint")
        #expect(modelFailure(URLError(.timedOut), config: config).hasSuffix("did not answer in 4000 ms"))
    }
}

@Suite struct GlobalFileTests {
    @Test func globalTemplateIsWrittenOnce() throws {
        let file = try makeRepo().appendingPathComponent("nested/config.json")
        try Setup.createGlobalFile(at: file)
        #expect(try JSONValue.decode(jsonc: Data(contentsOf: file)) == .object([:]))
        #expect(!Setup.globalTemplate.contains("\"guide\""))
        try "{\"model\": \"m\"}".write(to: file, atomically: true, encoding: .utf8)
        try Setup.createGlobalFile(at: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "{\"model\": \"m\"}")
    }
}

@Suite struct SchemaTests {
    /// The VS Code schema lists every field, with the default that `Config` has.
    @Test func schemaMatchesConfig() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../editors/vscode/schemas/plan-complete.schema.json").standardizedFileURL
        let schema = try JSONValue.decode(Data(contentsOf: file))
        func defaults(_ node: JSONValue) -> JSONValue {
            var fields: [String: JSONValue] = [:]
            for (key, property) in node["properties"]?.objectValue ?? [:] {
                fields[key] = property["properties"] == nil ? property["default"] ?? .null : defaults(property)
            }
            return .object(fields)
        }
        var config = try JSONValue.decode(JSONEncoder().encode(Config())).objectValue ?? [:]
        config["apiKey"] = .null
        let listed = defaults(schema)
        #expect(listed.objectValue?.keys.sorted() == config.keys.sorted())
        #expect(try Config().merged(with: listed) == Config())
        for key in ["context", "scoring"] {
            #expect(listed[key]?.objectValue?.keys.sorted() == config[key]?.objectValue?.keys.sorted())
        }
    }
}

@Suite struct VersionTests {
    @Test func extensionHasTheServerVersion() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../editors/vscode/package.json").standardizedFileURL
        #expect(try JSONValue.decode(Data(contentsOf: file))["version"]?.stringValue == PlanComplete.version)
    }
}
