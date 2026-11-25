import Foundation

public func relativePath(of url: URL, to root: URL) -> String {
    let file = url.standardizedFileURL.resolvingSymlinksInPath()
    let parts = file.pathComponents
    let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    guard parts.count > base.count, zip(parts, base).allSatisfy(samePathComponent) else {
        return file.path.replacingOccurrences(of: "\\", with: "/")
    }
    return parts.dropFirst(base.count).joined(separator: "/")
}

private func samePathComponent(_ a: String, _ b: String) -> Bool {
    #if os(Windows)
    return a.caseInsensitiveCompare(b) == .orderedSame
    #else
    return a == b
    #endif
}
