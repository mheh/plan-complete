import Foundation
import Testing
import PlanCompleteCore
@testable import PlanCompleteLSP

final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [JSONValue] = []
    func append(_ m: JSONValue) { lock.withLock { _messages.append(m) } }
    var messages: [JSONValue] { lock.withLock { _messages } }
}

struct SlowProvider: CompletionProvider {
    let reply: String
    let delayMs: Int
    func complete(_ request: CompletionRequest) async throws -> String {
        try await Task.sleep(for: .milliseconds(delayMs))
        return reply
    }
}

@Suite struct LSPServerTests {
    func makeServer(reply: String, delayMs: Int = 0) -> (LSPServer, Box) {
        let box = Box()
        let server = LSPServer(send: { box.append($0) }, makeEngine: { root, config in
            var c = config
            c.debounceMs = 0
            return Engine(root: root, config: c, provider: SlowProvider(reply: reply, delayMs: delayMs))
        })
        return (server, box)
    }

    func waitFor(_ box: Box, id: Int) async throws -> JSONValue {
        for _ in 0..<200 {
            if let m = box.messages.first(where: { $0["id"] == .int(id) }) { return m }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CancellationError()
    }

    func open(_ server: LSPServer, text: String) async {
        await server.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                             "params": ["rootUri": "file:///tmp/pc-lsp-test", "capabilities": .object([:])]])
        await server.handle(["jsonrpc": "2.0", "method": "textDocument/didOpen",
                             "params": ["textDocument": ["uri": "file:///tmp/pc-lsp-test/a.swift", "languageId": "swift",
                                                         "version": 1, "text": .string(text)]]])
    }

    func request(_ id: Int, line: Int, character: Int, context: JSONValue = ["triggerKind": 2]) -> JSONValue {
        ["jsonrpc": "2.0", "id": .int(id), "method": "textDocument/inlineCompletion",
         "params": ["textDocument": ["uri": "file:///tmp/pc-lsp-test/a.swift"],
                    "position": ["line": .int(line), "character": .int(character)], "context": context]]
    }

    @Test func capabilitiesAndCompletion() async throws {
        let (server, box) = makeServer(reply: "return a + b")
        await open(server, text: "func add() {\n    \n}")
        let initReply = try await waitFor(box, id: 1)
        #expect(initReply["result"]?["capabilities"]?["inlineCompletionProvider"] == .object([:]))
        await server.handle(request(2, line: 1, character: 4))
        let reply = try await waitFor(box, id: 2)
        let item = reply["result"]?["items"]?.arrayValue?.first
        #expect(item?["insertText"] == "return a + b")
        #expect(item?["range"]?["start"]?["character"] == 4)
    }

    @Test func incrementalEditsApply() async throws {
        let (server, box) = makeServer(reply: "x")
        await open(server, text: "let a = 1\n")
        await server.handle(["jsonrpc": "2.0", "method": "textDocument/didChange",
                             "params": ["textDocument": ["uri": "file:///tmp/pc-lsp-test/a.swift", "version": 2],
                                        "contentChanges": [["range": ["start": ["line": 1, "character": 0],
                                                                      "end": ["line": 1, "character": 0]],
                                                            "text": "let b = "]]]])
        await server.handle(request(3, line: 1, character: 8))
        let reply = try await waitFor(box, id: 3)
        #expect(reply["result"]?["items"]?.arrayValue?.count == 1)
    }

    @Test func newerRequestCancelsOlder() async throws {
        let (server, box) = makeServer(reply: "slow", delayMs: 300)
        await open(server, text: "a\nb\n")
        await server.handle(request(10, line: 0, character: 1))
        await server.handle(request(11, line: 1, character: 1))
        let first = try await waitFor(box, id: 10)
        let second = try await waitFor(box, id: 11)
        #expect(first["result"]?["items"]?.arrayValue?.isEmpty == true)
        #expect(second["result"]?["items"]?.arrayValue?.count == 1)
    }

    @Test func selectedPopupItem() async throws {
        let (server, box) = makeServer(reply: "(capacity: 10)")
        await open(server, text: "cache.sto\n")
        let context: JSONValue = ["triggerKind": 2, "selectedCompletionInfo": [
            "text": "store", "range": ["start": ["line": 0, "character": 6], "end": ["line": 0, "character": 9]]]]
        await server.handle(request(4, line: 0, character: 9, context: context))
        let item = try await waitFor(box, id: 4)["result"]?["items"]?.arrayValue?.first
        #expect(item?["insertText"] == "store(capacity: 10)")
        #expect(item?["range"]?["start"]?["character"] == 6)
    }

    @Test func shutdownAndExit() async throws {
        let (server, box) = makeServer(reply: "")
        await server.handle(["jsonrpc": "2.0", "id": 9, "method": "shutdown"])
        _ = try await waitFor(box, id: 9)
        await server.handle(["jsonrpc": "2.0", "method": "exit"])
        #expect(await server.exitCode == 0)
    }

    @Test func framing() throws {
        var reader = MessageReader()
        let framed = try MessageReader.frame(["a": 1])
        reader.append(framed.prefix(10))
        #expect(try reader.next() == nil)
        reader.append(framed.dropFirst(10) + framed)
        #expect(try reader.next() == ["a": 1])
        #expect(try reader.next() == ["a": 1])
        #expect(try reader.next() == nil)
    }
}
