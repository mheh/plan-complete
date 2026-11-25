import Foundation
import PlanCompleteCore

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
    var config = Config()
    do {
        config = try Config.load(root: root)
        if args.contains("--no-guide") { config.useGuide = false }
        if args.contains("--no-scope") { config.useScope = false }
        let text = try String(contentsOf: file, encoding: .utf8)
        let document = TextDocument(path: file.path, text: text)
        let lineText = text.components(separatedBy: "\n").dropFirst(line - 1).first ?? ""
        let utf16Column = String(lineText.prefix(max(0, column - 1))).utf16.count
        let engine = Engine(root: root, config: config)
        let state = await engine.state()
        if args.contains("--no-guide") { await engine.setBypassPlanRule(true) }
        else if !state.isOn {
            printError("off: \(state.reason) in \(root.path)")
            if state == .noConfig { printError("run: plan-complete enable \(root.path)") }
            return 3
        }
        if args.contains("--prompt") {
            let prepared = await engine.prepare(document: document, line: line - 1, utf16Column: utf16Column)
            print(OpenAIFIMProvider.prompt(for: prepared.request))
            return 0
        }
        let start = Date()
        let completion = try await engine.complete(document: document, line: line - 1, utf16Column: utf16Column)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        printError("[\(ms) ms] context: \(completion.sources.joined(separator: ", "))")
        if args.contains("--raw") { printError("raw: \(completion.raw.debugDescription)") }
        print(completion.text)
        return 0
    } catch let error as DecodingError {
        printError("error: bad settings: \(error)")
        return 1
    } catch {
        printError("error: \(modelFailure(error, config: config))")
        return 1
    }
}
