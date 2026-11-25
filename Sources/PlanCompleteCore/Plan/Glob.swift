/// `*` within a path part, `**` across parts, `?` one character. No slash: match the file name.
public enum Glob {
    public static func matches(_ pattern: String, path: String) -> Bool {
        let p = Array(pattern.utf8)
        let s = Array(path.utf8)
        if !p.contains(UInt8(ascii: "/")) {
            let name = s.split(separator: UInt8(ascii: "/")).last.map(Array.init) ?? s
            return match(p[...], name[...])
        }
        return match(p[...], s[...])
    }

    private static func match(_ p: ArraySlice<UInt8>, _ s: ArraySlice<UInt8>) -> Bool {
        let slash = UInt8(ascii: "/"), star = UInt8(ascii: "*"), question = UInt8(ascii: "?")
        guard let first = p.first else { return s.isEmpty }
        if first == star {
            if p.dropFirst().first == star {
                var rest = p.dropFirst(2)
                if rest.first == slash { rest = rest.dropFirst() }
                if match(rest, s) { return true }
                var index = s.startIndex
                while index < s.endIndex {
                    if s[index] == slash, match(rest, s[(index + 1)...]) { return true }
                    index += 1
                }
                return rest.isEmpty
            }
            let rest = p.dropFirst()
            var index = s.startIndex
            while true {
                if match(rest, s[index...]) { return true }
                if index == s.endIndex || s[index] == slash { return false }
                index += 1
            }
        }
        guard let c = s.first else { return false }
        if first == question { return c != slash && match(p.dropFirst(), s.dropFirst()) }
        return first == c && match(p.dropFirst(), s.dropFirst())
    }
}
