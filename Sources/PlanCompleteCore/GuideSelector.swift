public struct GuideSelector: Sendable {
    public var budget: Int

    public init(budget: Int) { self.budget = budget }

    public struct Scored: Sendable, Equatable {
        public var chunk: GuideChunk
        public var score: Double
    }

    public func select(chunks: [GuideChunk], path: String, window: String) -> [GuideChunk] {
        scored(chunks: chunks, path: path, window: window).map(\.chunk)
    }

    public func scored(chunks: [GuideChunk], path: String, window: String) -> [Scored] {
        let words = Self.words(in: window)
        var results: [(Scored, Int)] = []
        for (index, chunk) in chunks.enumerated() {
            let score = Self.score(chunk, path: path, words: words)
            if score > 0 { results.append((Scored(chunk: chunk, score: score), index)) }
        }
        results.sort { $0.0.score != $1.0.score ? $0.0.score > $1.0.score : $0.1 < $1.1 }
        var used = 0
        var kept: [Scored] = []
        for (item, _) in results where used + item.chunk.tokenEstimate <= budget {
            kept.append(item)
            used += item.chunk.tokenEstimate
        }
        return kept
    }

    static func score(_ chunk: GuideChunk, path: String, words: Set<String>) -> Double {
        var score = 0.0
        let fileMatch = chunk.files.contains { Glob.matches($0, path: path) }
        if fileMatch { score += 10 }
        let hits = chunk.symbols.filter { symbol in
            symbolParts(symbol).contains { words.contains($0) }
        }
        score += Double(hits.count) * 4
        if let heading = chunk.heading, Self.words(in: heading).contains(where: { $0.count > 3 && words.contains($0) }) {
            score += 2
        }
        let chunkWords = Self.words(in: chunk.text).filter { $0.count > 3 }
        if !chunkWords.isEmpty {
            let overlap = chunkWords.filter { words.contains($0) }.count
            score += 3 * Double(overlap) / Double(chunkWords.count)
        }
        if chunk.files.isEmpty && chunk.symbols.isEmpty { score += 0.5 }
        guard score > 0 else { return 0 }
        return score + Double(chunk.priority)
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
            if CharacterSetLike.isIdentifier(ch) { current.unicodeScalars.append(ch) }
            else if !current.isEmpty { result.insert(current); current = "" }
        }
        if !current.isEmpty { result.insert(current) }
        return result
    }
}

enum CharacterSetLike {
    static func isIdentifier(_ s: Unicode.Scalar) -> Bool {
        s == "_" || s.properties.isAlphabetic || ("0"..."9").contains(s)
    }
}
