import Testing
@testable import PlanCompleteCore

@Suite struct TextTests {
    @Test func utf16Positions() {
        let doc = TextDocument(path: "a.swift", text: "let a = \"😀x\"\nnext")
        let index = doc.index(line: 0, utf16Column: 11)
        #expect(doc.text[index...].hasPrefix("x"))
        #expect(doc.text[doc.index(line: 1, utf16Column: 99)...].isEmpty)
        #expect(doc.text[doc.index(line: 5, utf16Column: 0)...].isEmpty)
    }

    @Test func incrementalChange() {
        var doc = TextDocument(path: "a", text: "hello\nworld")
        doc.apply(range: ((1, 0), (1, 5)), text: "there")
        #expect(doc.text == "hello\nthere")
        doc.apply(range: nil, text: "new")
        #expect(doc.text == "new")
    }

    @Test func contextLines() {
        let doc = TextDocument(path: "a", text: "1\n2\n3\n4\n5")
        let context = doc.context(line: 2, utf16Column: 1, prefixLines: 1, suffixLines: 1)
        #expect(context.prefix == "2\n3")
        #expect(context.suffix == "\n4")
        #expect(context.linePrefix == "3")
    }

    @Test func stripsRepeatedLineRest() {
        let cleaned = Postprocess.clean("data, for: url)", linePrefix: "cache.store(", suffix: ")\n}", maxLines: 5)
        #expect(cleaned == "data, for: url")
    }

    @Test func stopsAtFollowingCode() {
        let raw = "let x = 1\n    return x\n}"
        let cleaned = Postprocess.clean(raw, linePrefix: "    ", suffix: "\n    return x\n}", maxLines: 10)
        #expect(cleaned == "let x = 1")
    }

    @Test func stopsWhenLeavingBlock() {
        let raw = "a()\n    b()\n}\nfunc other() {"
        let cleaned = Postprocess.clean(raw, linePrefix: "    ", suffix: "", maxLines: 10)
        #expect(cleaned == "a()\n    b()")
    }

    @Test func removesFIMTokens() {
        #expect(Postprocess.clean("x<|file_sep|>junk", linePrefix: "", suffix: "", maxLines: 3) == "x")
    }
}
