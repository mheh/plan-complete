import Foundation
import PlanCompleteCore

public actor LSPServer {
    public typealias Send = @Sendable (JSONValue) async -> Void

    private let send: Send
    private let makeEngine: @Sendable (URL, Config) -> Engine
    private var engine: Engine?
    private var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    private var initOptions: JSONValue?
    private var documents: [String: TextDocument] = [:]
    private var pending: [String: (id: JSONValue, task: Task<Void, Never>)] = [:]
    private var tasksByID: [JSONValue: Task<Void, Never>] = [:]
    private var shutdownRequested = false
    private var enabled = true
    private var lastState: PlanState?
    public private(set) var exitCode: Int32?

    public init(send: @escaping Send,
                makeEngine: @escaping @Sendable (URL, Config) -> Engine = { Engine(root: $0, config: $1) }) {
        self.send = send
        self.makeEngine = makeEngine
    }

    public func handle(_ message: JSONValue) async {
        guard let method = message["method"]?.stringValue else { return }
        if method == "textDocument/inlineCompletion" { trace("request \(message["id"].map { "\($0)" } ?? "-") \(message["params"]?["position"].map { "\($0)" } ?? "")") }
        let id = message["id"]
        let params = message["params"] ?? .null
        switch method {
        case "initialize":
            await initialize(params)
            await reply(id, result: capabilities())
        case "initialized":
            await publishState(force: true)
        case "$/setTrace", "workspace/didChangeWatchedFiles":
            break
        case "planComplete/setEnabled":
            enabled = params["enabled"]?.boolValue ?? true
            await engine?.setEnabled(enabled)
            await publishState(force: true)
            await reply(id, result: ["state": stateJSON(lastState)])
        case "planComplete/status":
            await publishState(force: false)
            await reply(id, result: stateJSON(lastState))
        case "shutdown":
            shutdownRequested = true
            cancelAll()
            await reply(id, result: .null)
        case "exit":
            exitCode = shutdownRequested ? 0 : 1
        case "textDocument/didOpen":
            let doc = params["textDocument"]
            if let uri = doc?["uri"]?.stringValue, let text = doc?["text"]?.stringValue {
                documents[uri] = TextDocument(path: Self.path(of: uri), text: text)
            }
            await publishState(force: false)
        case "textDocument/didChange":
            didChange(params)
            await publishState(force: false)
        case "textDocument/didClose":
            if let uri = params["textDocument"]?["uri"]?.stringValue {
                documents[uri] = nil
                pending.removeValue(forKey: uri)?.task.cancel()
            }
        case "workspace/didChangeConfiguration":
            if let settings = params["settings"]?["planComplete"] {
                initOptions = settings
                await reloadConfig()
            }
        case "textDocument/didSave":
            await publishState(force: false)
        case "textDocument/inlineCompletion":
            guard let id else { return }
            await publishState(force: false)
            inlineCompletion(id: id, params: params)
        case "$/cancelRequest":
            if let target = params["id"], let task = tasksByID[target] { task.cancel() }
        default:
            if let id { await replyError(id, code: -32601, message: "method not found: \(method)") }
        }
    }

    private func capabilities() -> JSONValue {
        [
            "capabilities": [
                "textDocumentSync": ["openClose": true, "change": 2, "save": .object([:])],
                "inlineCompletionProvider": .object([:]),
            ],
            "serverInfo": ["name": "plan-complete", "version": "0.1.0"],
        ]
    }

    private func initialize(_ params: JSONValue) async {
        if let uri = params["workspaceFolders"]?.arrayValue?.first?["uri"]?.stringValue
            ?? params["rootUri"]?.stringValue {
            root = URL(fileURLWithPath: Self.path(of: uri), isDirectory: true)
        } else if let path = params["rootPath"]?.stringValue {
            root = URL(fileURLWithPath: path, isDirectory: true)
        }
        initOptions = params["initializationOptions"]
        await reloadConfig()
    }

    private func reloadConfig() async {
        var config = Config()
        do {
            config = try Config.load(root: root).applyingEditor(initOptions)
        } catch {
            log("config: \(error)")
        }
        let engine = makeEngine(root, config)
        await engine.setEnabled(enabled)
        self.engine = engine
        await publishState(force: true)
    }

    /// Sends `planComplete/status` when the state changed, or always with `force`.
    private func publishState(force: Bool) async {
        guard let engine else { return }
        let state = await engine.state()
        guard force || state != lastState else { return }
        let changed = state != lastState
        lastState = state
        if changed { trace("plan: \(state.isOn ? "on" : "off") (\(state.reason))") }
        await send(["jsonrpc": "2.0", "method": "planComplete/status", "params": stateJSON(state)])
    }

    private func stateJSON(_ state: PlanState?) -> JSONValue {
        guard let state else { return ["active": false, "reason": "starting"] }
        return ["active": .bool(state.isOn), "reason": .string(state.reason)]
    }

    private func didChange(_ params: JSONValue) {
        guard let uri = params["textDocument"]?["uri"]?.stringValue, var doc = documents[uri],
              let changes = params["contentChanges"]?.arrayValue else { return }
        for change in changes {
            guard let text = change["text"]?.stringValue else { continue }
            doc.apply(range: change["range"].flatMap(Self.range), text: text)
        }
        documents[uri] = doc
    }

    private func inlineCompletion(id: JSONValue, params: JSONValue) {
        guard let uri = params["textDocument"]?["uri"]?.stringValue,
              let line = params["position"]?["line"]?.intValue,
              let character = params["position"]?["character"]?.intValue,
              var document = documents[uri], let engine
        else {
            Task { await reply(id, result: ["items": []]) }
            return
        }

        var insertPrefix = ""
        var start = (line, character)
        var cursor = (line, character)
        if let selected = params["context"]?["selectedCompletionInfo"],
           let text = selected["text"]?.stringValue, let range = selected["range"].flatMap(Self.range) {
            document.apply(range: range, text: text)
            start = range.start
            let lines = text.components(separatedBy: "\n")
            cursor = lines.count == 1
                ? (range.start.0, range.start.1 + text.utf16.count)
                : (range.start.0 + lines.count - 1, lines.last?.utf16.count ?? 0)
            insertPrefix = text
        }
        let editorContext = (params["extraContext"]?.arrayValue ?? []).compactMap { item -> ExtraFile? in
            guard let path = item["path"]?.stringValue, let text = item["text"]?.stringValue else { return nil }
            return ExtraFile(path: path, text: text)
        }

        pending.removeValue(forKey: uri)?.task.cancel()
        let snapshot = document
        let finalCursor = cursor
        let rangeStart = start
        let original = (line, character)
        let task = Task { [weak self] in
            guard let self else { return }
            let debounce = await engine.config.debounceMs
            var items: [JSONValue] = []
            do {
                if debounce > 0 { try await Task.sleep(for: .milliseconds(debounce)) }
                let completion = try await engine.complete(document: snapshot, line: finalCursor.0,
                                                           utf16Column: finalCursor.1, editorContext: editorContext)
                if !completion.text.isEmpty {
                    items = [[
                        "insertText": .string(insertPrefix + completion.text),
                        "range": Self.rangeJSON(rangeStart, original),
                    ]]
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                await self.log("completion: \(error)")
            }
            if Task.isCancelled {
                await self.trace("cancelled \(id)")
                await self.finish(uri: uri, id: id, cancelled: true)
            } else {
                await self.trace("reply \(id) \(items)")
                await self.reply(id, result: ["items": .array(items)])
                await self.finish(uri: uri, id: id, cancelled: false)
            }
        }
        pending[uri] = (id, task)
        tasksByID[id] = task
    }

    private func finish(uri: String, id: JSONValue, cancelled: Bool) async {
        tasksByID[id] = nil
        if pending[uri]?.id == id { pending[uri] = nil }
        if cancelled { await reply(id, result: ["items": []]) }
    }

    private func cancelAll() {
        for (_, entry) in pending { entry.task.cancel() }
    }

    private func reply(_ id: JSONValue?, result: JSONValue) async {
        guard let id else { return }
        await send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func replyError(_ id: JSONValue, code: Int, message: String) async {
        await send(["jsonrpc": "2.0", "id": id, "error": ["code": .int(code), "message": .string(message)]])
    }

    private func log(_ text: String) {
        FileHandle.standardError.write(Data("plan-complete: \(text)\n".utf8))
        trace(text)
    }

    private static let tracePath = ProcessInfo.processInfo.environment["PLAN_COMPLETE_LOG"]

    private func trace(_ text: String) {
        guard let path = Self.tracePath else { return }
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile()
        handle.write(Data("\(Date().timeIntervalSince1970) \(text)\n".utf8))
        try? handle.close()
    }

    static func path(of uri: String) -> String {
        guard uri.hasPrefix("file:"), let url = URL(string: uri) else { return uri }
        return url.path
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

extension LSPServer {
    public static func runStdio() async {
        let output = StdoutWriter()
        let server = LSPServer(send: { message in await output.write(message) })
        var reader = MessageReader()
        for await chunk in stdinChunks() {
            reader.append(chunk)
            while true {
                do {
                    guard let message = try reader.next() else { break }
                    await server.handle(message)
                    if let code = await server.exitCode { exit(code) }
                } catch {
                    FileHandle.standardError.write(Data("plan-complete: bad message: \(error)\n".utf8))
                }
            }
        }
        exit(await server.exitCode ?? 0)
    }

    static func stdinChunks() -> AsyncStream<Data> {
        AsyncStream { continuation in
            let thread = Thread {
                while true {
                    let data = FileHandle.standardInput.availableData
                    if data.isEmpty { break }
                    continuation.yield(data)
                }
                continuation.finish()
            }
            thread.start()
        }
    }
}

actor StdoutWriter {
    func write(_ message: JSONValue) {
        guard let data = try? MessageReader.frame(message) else { return }
        FileHandle.standardOutput.write(data)
    }
}
