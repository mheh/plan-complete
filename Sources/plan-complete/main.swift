import Foundation
import PlanCompleteCore
import PlanCompleteLSP

let usage = """
usage:
  plan-complete serve                       LSP over stdio
  plan-complete probe FILE:LINE:COL [opts]  one completion; LINE and COL are 1-based
    --root DIR       workspace root (default: nearest parent with .plan-complete.json or .git)
    --no-guide       leave the guide out
    --no-scope       leave the scope summary out
    --prompt         print the request instead of calling the model
    --raw            also print the raw model text
"""

func findRoot(from start: URL) -> URL {
    var dir = start.hasDirectoryPath ? start : start.deletingLastPathComponent()
    while dir.path != "/" {
        for marker in [Config.fileName, ".git"] where FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path) {
            return dir
        }
        dir.deleteLastPathComponent()
    }
    return start.deletingLastPathComponent()
}

func probe(_ args: [String]) async -> Int32 {
    guard let target = args.first else { print(usage); return 2 }
    let parts = target.split(separator: ":").map(String.init)
    guard parts.count >= 3, let line = Int(parts[parts.count - 2]), let column = Int(parts[parts.count - 1]) else {
        print(usage); return 2
    }
    let file = URL(fileURLWithPath: parts.dropLast(2).joined(separator: ":")).standardizedFileURL
    var root = findRoot(from: file)
    if let index = args.firstIndex(of: "--root"), index + 1 < args.count {
        root = URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }
    do {
        var config = try Config.load(root: root)
        if args.contains("--no-guide") { config.useGuide = false }
        if args.contains("--no-scope") { config.useScope = false }
        let text = try String(contentsOf: file, encoding: .utf8)
        let document = TextDocument(path: file.path, text: text)
        let lineText = text.components(separatedBy: "\n").dropFirst(line - 1).first ?? ""
        let utf16Column = String(lineText.prefix(max(0, column - 1))).utf16.count
        let engine = Engine(root: root, config: config)
        if args.contains("--prompt") {
            let prepared = await engine.prepare(document: document, line: line - 1, utf16Column: utf16Column)
            print(OpenAIFIMProvider.prompt(for: prepared.request))
            return 0
        }
        let start = Date()
        let completion = try await engine.complete(document: document, line: line - 1, utf16Column: utf16Column)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        FileHandle.standardError.write(Data("[\(ms) ms] context: \(completion.sources.joined(separator: ", "))\n".utf8))
        if args.contains("--raw") { FileHandle.standardError.write(Data("raw: \(completion.raw.debugDescription)\n".utf8)) }
        print(completion.text)
        return 0
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 1
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "serve":
    await LSPServer.runStdio()
case "probe":
    exit(await probe(Array(arguments.dropFirst())))
default:
    print(usage)
    exit(arguments.isEmpty ? 0 : 2)
}
