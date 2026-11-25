import Foundation

public struct GuideChunk: Sendable, Equatable {
    public var source: String
    public var heading: String?
    public var files: [String]
    public var symbols: [String]
    public var priority: Int
    public var text: String

    public init(source: String, heading: String?, files: [String], symbols: [String], priority: Int, text: String) {
        self.source = source
        self.heading = heading
        self.files = files
        self.symbols = symbols
        self.priority = priority
        self.text = text
    }

    public var tokenEstimate: Int { max(1, (text.utf8.count + 3) / 4) }
}

public enum Guide {
    public struct FrontMatter: Sendable, Equatable {
        public var files: [String] = []
        public var symbols: [String] = []
        public var priority: Int = 0
    }

    public static func splitFrontMatter(_ markdown: String) -> (FrontMatter, String) {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return (FrontMatter(), markdown) }

        var fields: [String: [String]] = [:]
        var currentKey: String?
        for line in lines[1..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("- "), let key = currentKey {
                fields[key, default: []].append(unquote(String(trimmed.dropFirst(2))))
                continue
            }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            currentKey = key
            if value.hasPrefix("[") && value.hasSuffix("]") {
                fields[key] = value.dropFirst().dropLast()
                    .split(separator: ",")
                    .map { unquote(String($0)) }
                    .filter { !$0.isEmpty }
            } else if !value.isEmpty {
                fields[key] = [unquote(value)]
            } else {
                fields[key] = []
            }
        }
        var front = FrontMatter()
        front.files = fields["files"] ?? []
        front.symbols = fields["symbols"] ?? []
        front.priority = fields["priority"]?.first.flatMap { Int($0) } ?? 0
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (front, body)
    }

    /// One chunk per `## ` or `### ` section, plus one for text before the first section.
    public static func parse(markdown: String, source: String) -> [GuideChunk] {
        let (front, body) = splitFrontMatter(markdown)
        var chunks: [GuideChunk] = []
        var heading: String?
        var buffer: [String] = []
        var inFence = false

        func flush() {
            let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                chunks.append(GuideChunk(source: source, heading: heading, files: front.files,
                                         symbols: front.symbols, priority: front.priority, text: text))
            }
            buffer = []
        }

        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix("```") { inFence.toggle() }
            if !inFence, let level = headingLevel(line), level == 2 || level == 3 {
                flush()
                heading = String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            }
            buffer.append(line)
        }
        flush()
        return chunks
    }

    /// `path` is one Markdown file or a folder of them.
    public static func load(path: URL, root: URL) -> [GuideChunk] {
        let files = markdownFiles(at: path)
        return files.flatMap { url -> [GuideChunk] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return parse(markdown: text, source: relativePath(of: url, to: root))
        }
    }

    public static func markdownFiles(at path: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue { return [path] }
        guard let enumerator = FileManager.default.enumerator(at: path, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.path < $1.path }
    }

    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes > 0, line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    static func unquote(_ value: String) -> String {
        var v = value.trimmingCharacters(in: .whitespaces)
        if v.count >= 2, let first = v.first, let last = v.last, first == last, first == "\"" || first == "'" {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }
}

public func relativePath(of url: URL, to root: URL) -> String {
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    var base = root.standardizedFileURL.resolvingSymlinksInPath().path
    if !base.hasSuffix("/") { base += "/" }
    return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
}
