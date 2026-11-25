/// What encloses the cursor, from indentation and brackets only, so it works in any language.
public struct ScopeContext: Sendable, Equatable {
    /// Header lines of the enclosing blocks, outermost first.
    public var outline: [String]
    /// The name of the open call at the cursor: `self.init(` gives `init`.
    public var callee: String?
    /// Lines of this file that declare `callee`.
    public var definitions: [String]

    public var words: Set<String> {
        var result = GuideSelector.words(in: outline.joined(separator: "\n"))
        if let callee { result.insert(callee) }
        return result
    }

    public func summary(path: String) -> ExtraFile? {
        var parts: [String] = []
        if !outline.isEmpty {
            parts.append("Enclosing scope at the cursor in \(path):\n" + outline.joined(separator: "\n"))
        }
        if let callee, !definitions.isEmpty {
            parts.append("Declarations of `\(callee)` in \(path):\n" + definitions.joined(separator: "\n"))
        }
        guard !parts.isEmpty else { return nil }
        return ExtraFile(path: "\(path).scope", text: parts.joined(separator: "\n\n") + "\n")
    }

    public static func find(before: Substring, after: Substring, maxDefinitions: Int = 6) -> ScopeContext {
        let beforeLines = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let cursorLine = beforeLines.last ?? ""
        let callee = calleeName(in: cursorLine)

        let reference = cursorLine.trimmingCharacters(in: .whitespaces).isEmpty
            ? (beforeLines.dropLast().last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "")
            : cursorLine
        var indent = indentWidth(reference)
        var outline: [String] = []
        for line in beforeLines.dropLast().reversed() {
            if indent == 0 { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isCloser(trimmed) || isComment(trimmed) { continue }
            let width = indentWidth(line)
            if width < indent {
                outline.insert(trimmed, at: 0)
                indent = width
            }
        }

        var definitions: [String] = []
        if let callee {
            let afterLines = after.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().map(String.init)
            for line in beforeLines.dropLast() + afterLines where definitions.count < maxDefinitions {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if isDeclaration(of: callee, trimmed), !definitions.contains(trimmed) { definitions.append(trimmed) }
            }
        }
        return ScopeContext(outline: outline, callee: callee, definitions: definitions)
    }

    static func calleeName(in line: String) -> String? {
        var depth = 0
        var index = line.endIndex
        while index > line.startIndex {
            index = line.index(before: index)
            let ch = line[index]
            if ch == ")" || ch == "]" { depth += 1 }
            else if ch == "(" || ch == "[" {
                if depth == 0 {
                    guard ch == "(" else { return nil }
                    let name = line[..<index].reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                    return name.isEmpty ? nil : String(name.reversed())
                }
                depth -= 1
            }
        }
        return nil
    }

    static let declarationKeywords: Set<String> = [
        "func", "init", "def", "fn", "function", "fun", "class", "struct", "actor", "enum", "protocol",
        "interface", "type", "constructor", "convenience", "required", "override", "public", "private",
        "internal", "fileprivate", "open", "static", "async", "export", "pub", "mutating", "final",
    ]

    static func isDeclaration(of name: String, _ line: String) -> Bool {
        guard let range = line.range(of: name + "(") ?? line.range(of: name + "<") else { return false }
        if range.lowerBound > line.startIndex {
            let before = line[line.index(before: range.lowerBound)]
            if before.isLetter || before.isNumber || before == "_" || before == "." { return false }
        }
        let leading = line[..<range.lowerBound].split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if leading.isEmpty { return line.hasSuffix("{") || line.hasSuffix(":") }
        return leading.allSatisfy { declarationKeywords.contains($0) || $0.hasPrefix("@") }
    }

    static func isCloser(_ trimmed: String) -> Bool {
        guard let first = trimmed.first else { return false }
        return first == "}" || first == ")" || first == "]" || trimmed == "end" || trimmed.hasPrefix("end ")
    }

    static func isComment(_ trimmed: String) -> Bool {
        ["//", "#", "*", "/*", "--"].contains { trimmed.hasPrefix($0) }
    }

    static func indentWidth<S: StringProtocol>(_ line: S) -> Int { Postprocess.indentWidth(line) }
}
