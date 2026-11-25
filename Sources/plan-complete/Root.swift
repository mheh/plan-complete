import Foundation
import PlanCompleteCore

func findRoot(from start: URL) -> URL {
    var dir = start.hasDirectoryPath ? start : start.deletingLastPathComponent()
    while true {
        let found = [Config.fileName, Config.defaultGuide, ".git"].contains {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        if found { return dir }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path || dir.pathComponents.count <= 1 { break }
        dir = parent
    }
    return start.deletingLastPathComponent()
}
