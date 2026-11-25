import Foundation
import PlanCompleteCore

func directory(_ argument: String?) -> URL {
    let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    guard let argument else { return findRoot(from: current) }
    return URL(fileURLWithPath: argument, isDirectory: true).standardizedFileURL
}

func enable(_ root: URL) -> Int32 {
    do {
        let created = try Setup.enable(root: root)
        for name in created { print("wrote \(root.appendingPathComponent(name).path)") }
        let config = try Config.load(root: root)
        let state = PlanState.check(root: root, guide: config.guide)
        print(state.isOn ? "on: completions follow \(state.reason)" : "off: \(state.reason)")
        return 0
    } catch {
        printError("error: \(error.localizedDescription)")
        return 1
    }
}

func showConfig(_ root: URL) -> Int32 {
    do {
        let config = try Config.load(root: root)
        let state = PlanState.check(root: root, guide: config.guide)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        func mark(_ url: URL) -> String { FileManager.default.fileExists(atPath: url.path) ? "" : " (none)" }
        printError("global: \(Config.globalFile.path)\(mark(Config.globalFile))")
        printError("repo:   \(Config.repoFile(in: root).path)\(mark(Config.repoFile(in: root)))")
        printError("state:  \(state.isOn ? "on, follows \(state.reason)" : "off, \(state.reason)")")
        print(String(decoding: try encoder.encode(config.redacted), as: UTF8.self))
        return 0
    } catch {
        printError("error: \(error)")
        return 1
    }
}
