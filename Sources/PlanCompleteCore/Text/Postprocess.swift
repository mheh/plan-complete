public enum Postprocess {
    public static func clean(_ raw: String, linePrefix: String, suffix: String, maxLines: Int) -> String {
        var text = raw
        for token in fimStopStrings {
            if let range = text.range(of: token) { text = String(text[..<range.lowerBound]) }
        }
        if ScopeContext.calleeName(in: linePrefix) != nil { text = closeCall(text, lineRest: suffix.prefix { $0 != "\n" }) }
        var lines = text.components(separatedBy: "\n")
        let typed = linePrefix.trimmingCharacters(in: .whitespaces)
        if lines.count > 1, lines[0].trimmingCharacters(in: .whitespaces).isEmpty, !typed.isEmpty,
           lines[1].trimmingCharacters(in: .whitespaces).hasPrefix(typed) {
            let restated = lines[1].trimmingCharacters(in: .whitespaces)
            var rest = Substring(restated.dropFirst(typed.count))
            if linePrefix.last == " " { rest = rest.drop { $0 == " " } }
            lines = [String(rest)] + lines.dropFirst(2)
        }
        if typed.isEmpty, !linePrefix.isEmpty { lines = fitIndentedBlankLine(lines, indent: linePrefix) }
        if linePrefix.last == " ", !typed.isEmpty, let first = lines.first, first.first == " " {
            lines[0] = String(first.drop { $0 == " " })
        }
        if linePrefix.last == " ", let first = lines.first { lines[0] = dropRepeatedWords(first, after: typed) }
        if isCommentLine(typed) { lines = Array(lines.prefix(1)) }
        lines = cutLoop(lines)
        let lineRest = suffix.prefix { $0 != "\n" }
        let nextLine = suffix.components(separatedBy: "\n").dropFirst()
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces)
        let blankLine = linePrefix.allSatisfy { $0 == " " || $0 == "\t" }
        let baseIndent = indentWidth(blankLine ? linePrefix : String(linePrefix.prefix { $0 == " " || $0 == "\t" }))

        var kept: [String] = []
        for (index, line) in lines.enumerated() {
            if index > 0 {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let nextLine, !trimmed.isEmpty, trimmed == nextLine { break }
                if !trimmed.isEmpty, indentWidth(line) < baseIndent { break }
            }
            kept.append(line)
            if kept.count >= maxLines { break }
        }
        while let last = kept.last, kept.count > 1, last.trimmingCharacters(in: .whitespaces).isEmpty {
            kept.removeLast()
        }
        var result = kept.joined(separator: "\n")
        trimTrailingSpace(&result)

        let rest = lineRest.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty, !result.contains("\n"), result.hasSuffix(rest) {
            result = String(result.dropLast(rest.count))
            trimTrailingSpace(&result)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : result
    }

    /// Ends the completion where the call open at the cursor closes.
    static func closeCall(_ text: String, lineRest: Substring) -> String {
        var depth = 0
        for index in text.indices {
            switch text[index] {
            case "(", "[", "{": depth += 1
            case ")", "]", "}":
                depth -= 1
                if depth < 0 {
                    let closedByEditor = lineRest.trimmingCharacters(in: .whitespaces).first == text[index]
                    return String(text[..<(closedByEditor ? index : text.index(after: index))])
                }
            default: break
            }
        }
        return text
    }

    /// The cursor is after the indent of a blank line. The model sometimes starts on a new line and writes
    /// that indent again, or starts with one stray space.
    static func fitIndentedBlankLine(_ lines: [String], indent: String) -> [String] {
        var lines = lines
        let blank = lines.prefix { $0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        if blank > 0, blank < lines.count {
            lines.removeFirst(blank)
            if lines[0].hasPrefix(indent) { lines[0] = String(lines[0].dropFirst(indent.count)) }
        } else if let first = lines.first, first.hasPrefix(" "), !first.hasPrefix("  ") {
            lines[0] = String(first.dropFirst())
        }
        return lines
    }

    /// A small model can repeat a line, or a group of lines, until the token limit. Keeps the first copy:
    /// a group of two to four lines that comes twice in a row, or one line that comes three times.
    static func cutLoop(_ lines: [String]) -> [String] {
        let keys = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        for start in keys.indices {
            for size in 1...4 where start + size * 2 <= keys.count {
                let group = keys[start..<(start + size)]
                guard group.contains(where: { $0.count > 1 }) else { continue }
                let copies = size == 1 ? 3 : 2
                guard start + size * copies <= keys.count else { continue }
                let repeats = (1..<copies).allSatisfy { copy in
                    let from = start + size * copy
                    return keys[from..<(from + size)].elementsEqual(group)
                }
                if repeats { return Array(lines.prefix(start + size)) }
            }
        }
        return lines
    }

    /// `public var ` + `var x` gives `x`: drops leading words of the completion that end the typed text.
    static func dropRepeatedWords(_ line: String, after typed: String) -> String {
        let isWord: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "_" }
        let lead = line.prefix { $0 == " " }
        let body = line.dropFirst(lead.count)
        var cut = 0
        var index = body.startIndex
        while index < body.endIndex {
            let next = body.index(after: index)
            let atBoundary = next == body.endIndex || !isWord(body[next]) || !isWord(body[index])
            let head = body[..<next]
            if atBoundary, head.count >= 3, head.last.map(isWord) == true, typed.hasSuffix(head) {
                let before = typed.dropLast(head.count).last
                if before.map({ !isWord($0) }) ?? true { cut = head.count }
            }
            index = next
        }
        guard cut > 0 else { return line }
        return String(body.dropFirst(cut).drop { $0 == " " })
    }

    public static func isCommentLine(_ typed: String) -> Bool {
        ["//", "# ", "--", "/*", "* "].contains { typed.hasPrefix($0) }
    }

    static func trimTrailingSpace(_ text: inout String) {
        while let last = text.last, last == " " || last == "\t" { text.removeLast() }
    }

    static func indentWidth<S: StringProtocol>(_ line: S) -> Int {
        var width = 0
        for ch in line {
            if ch == " " { width += 1 } else if ch == "\t" { width += 4 } else { break }
        }
        return width
    }
}
