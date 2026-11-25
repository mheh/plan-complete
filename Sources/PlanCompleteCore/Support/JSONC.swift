import Foundation

/// JSON with `//` and `/* */` comments and trailing commas, as VS Code reads its settings.
public enum JSONC {
    public static func strip(_ text: String) -> String {
        var out: [Unicode.Scalar] = []
        let scalars = Array(text.unicodeScalars)
        var index = 0
        var inString = false
        while index < scalars.count {
            let scalar = scalars[index]
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            if inString {
                out.append(scalar)
                if scalar == "\\", let next {
                    out.append(next)
                    index += 1
                } else if scalar == "\"" {
                    inString = false
                }
            } else if scalar == "/", next == "/" {
                while index < scalars.count, scalars[index] != "\n" { index += 1 }
                continue
            } else if scalar == "/", next == "*" {
                index += 2
                while index < scalars.count, !(scalars[index] == "*" && index + 1 < scalars.count && scalars[index + 1] == "/") {
                    index += 1
                }
                index += 2
                continue
            } else {
                if scalar == "}" || scalar == "]", let last = out.lastIndex(where: { !$0.properties.isWhitespace }),
                   out[last] == "," {
                    out.remove(at: last)
                }
                if scalar == "\"" { inString = true }
                out.append(scalar)
            }
            index += 1
        }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: out)
        return String(result)
    }
}

extension JSONValue {
    public static func decode(jsonc data: Data) throws -> JSONValue {
        try decode(Data(JSONC.strip(String(decoding: data, as: UTF8.self)).utf8))
    }
}
