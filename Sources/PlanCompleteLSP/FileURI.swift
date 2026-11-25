import Foundation

extension LSPServer {
    static func path(of uri: String) -> String {
        guard uri.hasPrefix("file:"), let url = URL(string: uri) else { return uri }
        return localPath(url.path)
    }

    static func localPath(_ path: String, windows: Bool = isWindows) -> String {
        let chars = Array(path.prefix(3))
        guard windows, chars.count == 3, chars[0] == "/", chars[1].isLetter, chars[2] == ":" else { return path }
        return String(path.dropFirst())
    }

    static var isWindows: Bool {
        #if os(Windows)
        return true
        #else
        return false
        #endif
    }
}
