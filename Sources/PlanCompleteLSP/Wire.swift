import Foundation
import PlanCompleteCore

extension LSPServer {
    func reply(_ id: JSONValue?, result: JSONValue) async {
        guard let id else { return }
        await send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    func replyError(_ id: JSONValue, code: Int, message: String) async {
        await send(["jsonrpc": "2.0", "id": id, "error": ["code": .int(code), "message": .string(message)]])
    }

    func log(_ text: String) {
        FileHandle.standardError.write(Data("plan-complete: \(text)\n".utf8))
        trace(text)
    }

    static let tracePath = ProcessInfo.processInfo.environment["PLAN_COMPLETE_LOG"]

    func trace(_ text: String) {
        guard let path = Self.tracePath else { return }
        if !FileManager.default.fileExists(atPath: path) {
            _ = FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile()
        handle.write(Data("\(Date().timeIntervalSince1970) \(text)\n".utf8))
        try? handle.close()
    }

    static func range(_ value: JSONValue) -> (start: (Int, Int), end: (Int, Int))? {
        guard let sl = value["start"]?["line"]?.intValue, let sc = value["start"]?["character"]?.intValue,
              let el = value["end"]?["line"]?.intValue, let ec = value["end"]?["character"]?.intValue
        else { return nil }
        return ((sl, sc), (el, ec))
    }

    static func rangeJSON(_ start: (Int, Int), _ end: (Int, Int)) -> JSONValue {
        ["start": ["line": .int(start.0), "character": .int(start.1)],
         "end": ["line": .int(end.0), "character": .int(end.1)]]
    }
}
