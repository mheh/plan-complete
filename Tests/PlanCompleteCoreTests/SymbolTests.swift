import Testing
@testable import PlanCompleteCore

@Suite struct SymbolTests {
    let chunks = Guide.parse(markdown: """
    ## Step 1: the cache

    `actor ResponseCache` in Sources/Net.swift holds at most `capacity` items.
    `func store(_ data: Data, for key: URL)` inserts.

    ## Step 2: the queue

    `actor RequestQueue` in Sources/Net.swift sends again after a failure.
    `func retry(_ request: URLRequest)` waits, then sends.
    """, source: "PLAN.md")

    func first(_ symbols: SymbolPath, scoring: Config.Scoring = .init()) -> String? {
        GuideSelector(budget: 1000, scoring: scoring)
            .select(chunks: chunks, path: "Sources/Net.swift", window: "", symbols: symbols).first?.heading
    }

    @Test func theEnclosingTypeBreaksATie() {
        #expect(first(SymbolPath()) == "Step 1: the cache")
        #expect(first(SymbolPath(parsing: "RequestQueue")) == "Step 2: the queue")
        #expect(first(SymbolPath(parsing: "ResponseCache")) == "Step 1: the cache")
    }

    @Test func theMemberCounts() {
        #expect(first(SymbolPath(parsing: "Other > retry(_:)")) == "Step 2: the queue")
    }

    @Test func theTypeOutweighsTheMember() {
        #expect(first(SymbolPath(parsing: "ResponseCache > retry(_:)")) == "Step 1: the cache")
        var scoring = Config.Scoring()
        scoring.type = 0
        #expect(first(SymbolPath(parsing: "ResponseCache > retry(_:)"), scoring: scoring) == "Step 2: the queue")
    }

    @Test func genericAndShortNamesAreIgnored() {
        let path = SymbolPath(parsing: "App > Key > init(capacity:)")
        #expect(path.typeNames.isEmpty)
        #expect(path.memberName == nil)
        #expect(SymbolPath(parsing: "ResponseCache > store(_:for:)").memberName == "store")
    }

    @Test func kindsOfTheProtocol() {
        let path = SymbolPath([.init(name: "ResponseCache", lspKind: 5), .init(name: "store(_:for:)", lspKind: 6)])
        #expect(path.symbols.map(\.isType) == [true, false])
        #expect(path.description == "ResponseCache > store(_:for:)")
        #expect(path == SymbolPath(parsing: "ResponseCache>store(_:for:)"))
    }

    @Test func theSettingTurnsItOff() async throws {
        let root = try makeRepo([".plan-complete.json": "{}", "PLAN.md": chunks.map(\.text).joined(separator: "\n\n")])
        let document = TextDocument(path: root.appendingPathComponent("Sources/Net.swift").path, text: "")
        let context = EditorContext(symbols: SymbolPath(parsing: "RequestQueue"))
        var config = Config()
        let on = await Engine(root: root, config: config, provider: RecordingProvider(reply: ""))
            .prepare(document: document, line: 0, utf16Column: 0, editorContext: context)
        config.context.symbols = false
        let off = await Engine(root: root, config: config, provider: RecordingProvider(reply: ""))
            .prepare(document: document, line: 0, utf16Column: 0, editorContext: context)
        #expect(on.guide.first?.heading == "Step 2: the queue")
        #expect(off.guide.first?.heading == "Step 1: the cache")
    }
}
