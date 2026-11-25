import Foundation
import Testing
@testable import PlanCompleteCore

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
    @Test func anIndentedBlankLineKeepsItsIndent() {
        #expect(Postprocess.clean(" store(a)", linePrefix: "    ", suffix: "\n}", maxLines: 5) == "store(a)")
        #expect(Postprocess.clean("\n        store(a)\n        b()", linePrefix: "        ", suffix: "\n}", maxLines: 5)
            == "store(a)\n        b()")
        #expect(Postprocess.clean("\n            deeper()", linePrefix: "        ", suffix: "\n}", maxLines: 5) == "    deeper()")
        #expect(Postprocess.clean("    store(a)", linePrefix: "", suffix: "\n}", maxLines: 5) == "    store(a)")
    }

    @Test func cutsALoop() {
        let pair = "push(url);\n    flush();\n    return n;\n    flush();\n    return n;\n    flush();\n    return n"
        #expect(Postprocess.clean(pair, linePrefix: "    ", suffix: "\n}", maxLines: 12) == "push(url);\n    flush();\n    return n;")
        #expect(Postprocess.cutLoop(["a()", "a()", "a()", "a()"]) == ["a()"])
    }

    @Test func keepsWhatOnlyLooksLikeALoop() {
        #expect(Postprocess.cutLoop(["a()", "a()", "b()"]) == ["a()", "a()", "b()"])
        #expect(Postprocess.cutLoop(["if a {", "    x()", "}", "if b {", "    x()", "}"]).count == 6)
        #expect(Postprocess.cutLoop(["x {", "}", "", "", "", "y"]).count == 6)
        #expect(Postprocess.cutLoop(["    }", "}", "}"]).count == 3)
    }

    @Test func noRepeatedKeyword() {
        #expect(Postprocess.clean("var fs_total: Int32 {", linePrefix: "public var ", suffix: "", maxLines: 4) == "fs_total: Int32 {")
        #expect(Postprocess.clean(" var fs_x: Int32", linePrefix: "public ", suffix: "", maxLines: 4) == "var fs_x: Int32")
        #expect(Postprocess.clean("variable = 1", linePrefix: "let ", suffix: "", maxLines: 4) == "variable = 1")
        #expect(Postprocess.clean("public var x", linePrefix: "public var ", suffix: "", maxLines: 4) == "x")
    }
}
