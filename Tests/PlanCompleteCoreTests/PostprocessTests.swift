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
    @Test func noRepeatedKeyword() {
        #expect(Postprocess.clean("var fs_total: Int32 {", linePrefix: "public var ", suffix: "", maxLines: 4) == "fs_total: Int32 {")
        #expect(Postprocess.clean(" var fs_x: Int32", linePrefix: "public ", suffix: "", maxLines: 4) == "var fs_x: Int32")
        #expect(Postprocess.clean("variable = 1", linePrefix: "let ", suffix: "", maxLines: 4) == "variable = 1")
        #expect(Postprocess.clean("public var x", linePrefix: "public var ", suffix: "", maxLines: 4) == "x")
    }
}
