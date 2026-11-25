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

@Suite struct CallTests {
    @Test func stopsAtCallClose() {
        let cleaned = Postprocess.clean("capacity: 100) {\n        self.capacity = capacity", linePrefix: "        self.init(", suffix: "\n    }", maxLines: 8)
        #expect(cleaned == "capacity: 100)")
    }

    @Test func leavesEditorParen() {
        let cleaned = Postprocess.clean("capacity: 100)", linePrefix: "self.init(", suffix: ")\n", maxLines: 8)
        #expect(cleaned == "capacity: 100")
    }

    @Test func nestedCalls() {
        let cleaned = Postprocess.clean("a(b), c) + 1", linePrefix: "f(", suffix: "", maxLines: 8)
        #expect(cleaned == "a(b), c)")
    }
}

@Suite struct CommentTests {
    @Test func restatedCommentLine() {
        let raw = "\n/// The total bytes read.\n/// Source: x\npublic var y"
        #expect(Postprocess.clean(raw, linePrefix: "/// The total ", suffix: "\n/// Source: x", maxLines: 8) == "bytes read.")
    }

    @Test func commentStaysOneLine() {
        #expect(Postprocess.clean("counts bytes.\nlet x = 1", linePrefix: "// This ", suffix: "", maxLines: 8) == "counts bytes.")
    }
}

@Suite struct SpacingTests {
    @Test func noDoubleSpace() {
        #expect(Postprocess.clean(" bytes read.", linePrefix: "/// The total ", suffix: "", maxLines: 4) == "bytes read.")
        #expect(Postprocess.clean("    return x", linePrefix: "    ", suffix: "", maxLines: 4) == "    return x")
    }
}

@Suite struct RepeatTests {
    @Test func noRepeatedKeyword() {
        #expect(Postprocess.clean("var fs_total: Int32 {", linePrefix: "public var ", suffix: "", maxLines: 4) == "fs_total: Int32 {")
        #expect(Postprocess.clean(" var fs_x: Int32", linePrefix: "public ", suffix: "", maxLines: 4) == "var fs_x: Int32")
        #expect(Postprocess.clean("variable = 1", linePrefix: "let ", suffix: "", maxLines: 4) == "variable = 1")
        #expect(Postprocess.clean("public var x", linePrefix: "public var ", suffix: "", maxLines: 4) == "x")
    }
}
