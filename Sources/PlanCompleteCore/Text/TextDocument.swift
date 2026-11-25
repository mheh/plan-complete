public struct TextDocument: Sendable, Equatable {
    public var path: String
    public var text: String

    public init(path: String, text: String) { self.path = path; self.text = text }

    /// LSP position: zero-based line, UTF-16 column. Columns past the line end clamp.
    public func index(line: Int, utf16Column: Int) -> String.Index {
        var lineStart = text.startIndex
        var current = 0
        while current < line {
            guard let newline = text[lineStart...].firstIndex(of: "\n") else { return text.endIndex }
            lineStart = text.index(after: newline)
            current += 1
        }
        let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
        let utf16 = text.utf16
        let start = lineStart.samePosition(in: utf16) ?? utf16.startIndex
        let end = lineEnd.samePosition(in: utf16) ?? utf16.endIndex
        let available = utf16.distance(from: start, to: end)
        var target = utf16.index(start, offsetBy: min(max(0, utf16Column), available))
        while target.samePosition(in: text) == nil && target > start { target = utf16.index(before: target) }
        return target.samePosition(in: text) ?? lineStart
    }

    public mutating func apply(range: (start: (Int, Int), end: (Int, Int))?, text newText: String) {
        guard let range else { text = newText; return }
        let lower = index(line: range.start.0, utf16Column: range.start.1)
        let upper = index(line: range.end.0, utf16Column: range.end.1)
        text.replaceSubrange(lower..<max(lower, upper), with: newText)
    }

    public struct Context: Sendable, Equatable {
        public var prefix: String
        public var suffix: String
        public var linePrefix: String
        public var window: String
        public var scope: ScopeContext
    }

    public func context(line: Int, utf16Column: Int, prefixLines: Int, suffixLines: Int, windowLines: Int = 20) -> Context {
        let cursor = index(line: line, utf16Column: utf16Column)
        let before = text[..<cursor]
        let after = text[cursor...]
        return Context(
            prefix: Self.lastLines(before, prefixLines),
            suffix: Self.firstLines(after, suffixLines),
            linePrefix: String(before[(before.lastIndex(of: "\n").map { before.index(after: $0) } ?? before.startIndex)...]),
            window: Self.lastLines(before, windowLines) + Self.firstLines(after, max(1, windowLines / 4)),
            scope: ScopeContext.find(before: before, after: after)
        )
    }

    static func lastLines(_ text: Substring, _ count: Int) -> String {
        var index = text.endIndex
        var seen = 0
        while index > text.startIndex {
            let previous = text.index(before: index)
            if text[previous] == "\n" {
                seen += 1
                if seen > count { break }
            }
            index = previous
        }
        return String(text[index...])
    }

    static func firstLines(_ text: Substring, _ count: Int) -> String {
        var index = text.startIndex
        var seen = 0
        while index < text.endIndex {
            if text[index] == "\n" {
                seen += 1
                if seen > count { break }
            }
            index = text.index(after: index)
        }
        return String(text[..<index])
    }
}
