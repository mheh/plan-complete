public struct GuideSelector: Sendable {
    public var budget: Int
    public var scoring: Config.Scoring

    public init(budget: Int, scoring: Config.Scoring = .init()) {
        self.budget = budget
        self.scoring = scoring
    }

    public struct Scored: Sendable, Equatable {
        public var chunk: GuideChunk
        public var score: Double
    }

    public func select(chunks: [GuideChunk], path: String, window: String,
                       symbols: SymbolPath = .init()) -> [GuideChunk] {
        scored(chunks: chunks, path: path, window: window, symbols: symbols).map(\.chunk)
    }

    public func scored(chunks: [GuideChunk], path: String, window: String,
                       symbols: SymbolPath = .init()) -> [Scored] {
        let words = Self.words(in: window)
        var results: [(Scored, Int)] = []
        for (index, chunk) in chunks.enumerated() {
            let score = score(chunk, path: path, words: words, symbols: symbols)
            if score > 0 { results.append((Scored(chunk: chunk, score: score), index)) }
        }
        // Sections with no tie to the file or the cursor only fill in when nothing else matches.
        if results.contains(where: { $0.0.score >= 1 + Double($0.0.chunk.priority) }) {
            results.removeAll { $0.0.score < 1 + Double($0.0.chunk.priority) }
        }
        results.sort { $0.0.score != $1.0.score ? $0.0.score > $1.0.score : $0.1 < $1.1 }
        var used = 0
        var kept: [Scored] = []
        for (item, _) in results {
            if used + item.chunk.tokenEstimate <= budget {
                kept.append(item)
                used += item.chunk.tokenEstimate
            }
        }
        if kept.isEmpty, var best = results.first?.0 {
            best.chunk.text = String(best.chunk.text.prefix(budget * 4))
            kept = [best]
        }
        return kept
    }

    func score(_ chunk: GuideChunk, path: String, words: Set<String>, symbols: SymbolPath = .init()) -> Double {
        var score = 0.0
        let fileMatch = chunk.files.contains { Glob.matches($0, path: path) }
        if fileMatch { score += scoring.glob } else if Self.mentions(chunk.text, path: path) { score += scoring.file }
        let hits = chunk.symbols.filter { symbol in
            Self.symbolParts(symbol).contains { words.contains($0) }
        }
        score += Double(hits.count) * scoring.symbol
        if chunk.symbols.isEmpty {
            let named = Self.codeSpanWords(chunk.text).filter { $0.count > 2 && words.contains($0) }
            score += Double(min(named.count, 3)) * scoring.codeSpan
        }
        if let heading = chunk.heading, Self.words(in: heading).contains(where: { $0.count > 3 && words.contains($0) }) {
            score += scoring.heading
        }
        let allWords = Self.words(in: chunk.text)
        if !symbols.typeNames.isDisjoint(with: allWords) { score += scoring.type }
        if let member = symbols.memberName, allWords.contains(member) { score += scoring.member }
        let chunkWords = allWords.filter { $0.count > 3 }
        if !chunkWords.isEmpty {
            let overlap = chunkWords.filter { words.contains($0) }.count
            score += scoring.words * Double(overlap) / Double(chunkWords.count)
        }
        if chunk.files.isEmpty && chunk.symbols.isEmpty { score += 0.5 }
        guard score > 0 else { return 0 }
        return score + Double(chunk.priority)
    }

    /// Plain Markdown names files in its text: `Sources/Net/Cache.swift`, or `Cache.swift`.
    static func mentions(_ text: String, path: String) -> Bool {
        if text.contains(path) { return true }
        guard let name = path.split(separator: "/").last, name.contains(".") else { return false }
        return text.contains(name)
    }

    /// Identifiers inside `code spans` of plain Markdown, which stand in for `symbols:`.
    static func codeSpanWords(_ text: String) -> Set<String> {
        let spans = text.split(separator: "`", omittingEmptySubsequences: false).enumerated()
            .filter { $0.offset % 2 == 1 }.map { String($0.element) }
        return words(in: spans.joined(separator: " "))
    }

    static func symbolParts(_ symbol: String) -> [String] {
        symbol.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") })
            .map(String.init)
            .filter { $0 != "_" && !$0.isEmpty }
    }

    public static func words(in text: String) -> Set<String> {
        var result = Set<String>()
        var current = ""
        for ch in text.unicodeScalars {
            if ch.isIdentifierPart { current.unicodeScalars.append(ch) }
            else if !current.isEmpty { result.insert(current); current = "" }
        }
        if !current.isEmpty { result.insert(current) }
        return result
    }
}

extension Unicode.Scalar {
    var isIdentifierPart: Bool { self == "_" || properties.isAlphabetic || ("0"..."9").contains(self) }
}
