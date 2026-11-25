import Testing
@testable import PlanCompleteCore

@Suite struct GuideTests {
    let sample = """
    ---
    files: ["Sources/Net/**", "*.swift"]
    symbols:
      - ResponseCache
      - "ResponseCache.store(_:for:)"
    priority: 2
    ---
    Intro line.

    ## ResponseCache
    An actor.
    ```
    ## not a heading
    ```

    ## Errors
    No force unwraps.
    """

    @Test func frontMatter() {
        let (front, body) = Guide.splitFrontMatter(sample)
        #expect(front.files == ["Sources/Net/**", "*.swift"])
        #expect(front.symbols == ["ResponseCache", "ResponseCache.store(_:for:)"])
        #expect(front.priority == 2)
        #expect(body.hasPrefix("Intro line."))
    }

    @Test func chunksBySection() {
        let chunks = Guide.parse(markdown: sample, source: "docs/guide/net.md")
        #expect(chunks.map(\.heading) == [nil, "ResponseCache", "Errors"])
        #expect(chunks[1].text.contains("## not a heading"))
        #expect(chunks.allSatisfy { $0.priority == 2 && $0.source == "docs/guide/net.md" })
    }

    @Test func noFrontMatter() {
        let chunks = Guide.parse(markdown: "Just text", source: "a.md")
        #expect(chunks.count == 1)
        #expect(chunks[0].files.isEmpty)
    }

    @Test func globs() {
        #expect(Glob.matches("Sources/Net/**", path: "Sources/Net/Cache.swift"))
        #expect(Glob.matches("Sources/Net/**", path: "Sources/Net/a/b.swift"))
        #expect(!Glob.matches("Sources/Net/**", path: "Sources/UI/View.swift"))
        #expect(Glob.matches("*.swift", path: "Sources/UI/View.swift"))
        #expect(Glob.matches("Sources/*/View.swift", path: "Sources/UI/View.swift"))
        #expect(!Glob.matches("Sources/*.swift", path: "Sources/UI/View.swift"))
        #expect(Glob.matches("**/View.?wift", path: "a/b/View.swift"))
    }

    @Test func selection() {
        let chunks = [
            GuideChunk(source: "a.md", heading: "Net", files: ["Sources/Net/**"], symbols: [], priority: 0, text: "net rules"),
            GuideChunk(source: "b.md", heading: "Cache", files: [], symbols: ["ResponseCache.store(_:for:)"], priority: 0, text: "cache rules"),
            GuideChunk(source: "c.md", heading: "UI", files: ["Sources/UI/**"], symbols: ["Button"], priority: 0, text: "ui rules"),
        ]
        let picked = GuideSelector(budget: 1000).select(chunks: chunks, path: "Sources/Net/Cache.swift", window: "await cache.store(data")
        #expect(picked.map(\.source) == ["a.md", "b.md"])
    }

    @Test func budget() {
        let big = String(repeating: "word ", count: 400)
        let chunks = [
            GuideChunk(source: "a.md", heading: nil, files: ["**"], symbols: [], priority: 1, text: big),
            GuideChunk(source: "b.md", heading: nil, files: ["**"], symbols: [], priority: 0, text: "small"),
        ]
        let picked = GuideSelector(budget: 100).select(chunks: chunks, path: "x.swift", window: "")
        #expect(picked.map(\.source) == ["b.md"])
    }
}
