import Foundation
@testable import PlanCompleteCore

actor RecordingProvider: CompletionProvider {
    private(set) var requests: [CompletionRequest] = []
    let reply: String
    init(reply: String) { self.reply = reply }
    func complete(_ request: CompletionRequest) async throws -> String {
        requests.append(request)
        return reply
    }
}

func makeRepo(_ files: [String: String] = [:]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for (path, text) in files {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    return root
}
