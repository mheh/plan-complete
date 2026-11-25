import Foundation
import PlanCompleteCore

public actor LSPServer {
    public typealias Send = @Sendable (JSONValue) async -> Void

    let send: Send
    let makeEngine: @Sendable (URL, Config) -> Engine
    var engine: Engine?
    var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    var initOptions: JSONValue?
    var documents: [String: TextDocument] = [:]
    var pending: [String: (id: JSONValue, task: Task<Void, Never>)] = [:]
    var tasksByID: [JSONValue: Task<Void, Never>] = [:]
    var shutdownRequested = false
    var enabled = true
    var lastState: PlanState?
    var problem: String?
    var context: JSONValue?
    public private(set) var exitCode: Int32?

    public init(send: @escaping Send,
                makeEngine: @escaping @Sendable (URL, Config) -> Engine = { Engine(root: $0, config: $1) }) {
        self.send = send
        self.makeEngine = makeEngine
    }

    public func handle(_ message: JSONValue) async {
        guard let method = message["method"]?.stringValue else { return }
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
        case "planComplete/enable":
            await enableRepository(id)
        case "planComplete/files":
            await reply(id, result: await files(createGlobal: params["createGlobal"]?.boolValue == true))
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
            if let uri = params["textDocument"]?["uri"]?.stringValue, isSettingsFile(Self.path(of: uri)) {
                await reloadConfig()
            } else {
                await publishState(force: false)
            }
        case "textDocument/inlineCompletion":
            guard let id else { return }
            trace("request \(id) \(params["position"] ?? .null)")
            await publishState(force: false)
            inlineCompletion(id: id, params: params)
        case "$/cancelRequest":
            if let target = params["id"], let task = tasksByID[target] { task.cancel() }
        default:
            if let id { await replyError(id, code: -32601, message: "method not found: \(method)") }
        }
    }

    func capabilities() -> JSONValue {
        [
            "capabilities": [
                "textDocumentSync": ["openClose": true, "change": 2, "save": .object([:])],
                "inlineCompletionProvider": .object([:]),
            ],
            "serverInfo": ["name": "plan-complete", "version": .string(PlanComplete.version)],
        ]
    }

    func initialize(_ params: JSONValue) async {
        if let uri = params["workspaceFolders"]?.arrayValue?.first?["uri"]?.stringValue
            ?? params["rootUri"]?.stringValue {
            root = URL(fileURLWithPath: Self.path(of: uri), isDirectory: true)
        } else if let path = params["rootPath"]?.stringValue {
            root = URL(fileURLWithPath: path, isDirectory: true)
        }
        initOptions = params["initializationOptions"]
        await reloadConfig()
    }

    func reloadConfig() async {
        var config = Config()
        problem = nil
        do {
            config = try Config.load(root: root).applyingEditor(initOptions)
        } catch {
            log("config: \(error)")
            problem = "the settings could not be read; the defaults apply. Run: plan-complete config"
        }
        context = try? JSONValue.decode(JSONEncoder().encode(config.context))
        let engine = makeEngine(root, config)
        await engine.setEnabled(enabled)
        self.engine = engine
        await publishState(force: true)
    }

    func publishState(force: Bool) async {
        guard let engine else { return }
        let state = await engine.state()
        guard force || state != lastState else { return }
        let changed = state != lastState
        lastState = state
        if changed { trace("plan: \(state.isOn ? "on" : "off") (\(state.reason))") }
        await send(["jsonrpc": "2.0", "method": "planComplete/status", "params": stateJSON(state)])
    }

    func stateJSON(_ state: PlanState?) -> JSONValue {
        guard let state else { return ["active": false, "reason": "starting"] }
        var fields: [String: JSONValue] = ["active": .bool(state.isOn), "reason": .string(state.reason)]
        if let problem { fields["problem"] = .string(problem) }
        if let context { fields["context"] = context }
        return .object(fields)
    }

    func enableRepository(_ id: JSONValue?) async {
        do {
            let created = try Setup.enable(root: root)
            await reloadConfig()
            await reply(id, result: ["created": .array(created.map { .string($0) }), "state": stateJSON(lastState)])
        } catch {
            if let id { await replyError(id, code: -32603, message: "\(error.localizedDescription)") }
        }
    }

    func isSettingsFile(_ path: String) -> Bool {
        let saved = URL(fileURLWithPath: path).standardizedFileURL.path
        return [Config.repoFile(in: root), Config.globalFile].contains { $0.standardizedFileURL.path == saved }
    }

    func files(createGlobal: Bool) async -> JSONValue {
        if createGlobal { try? Setup.createGlobalFile() }
        let guide = await engine?.config.guide ?? Config.defaultGuide
        return [
            "global": .string(Config.globalFile.path),
            "repo": .string(Config.repoFile(in: root).path),
            "plan": .string(root.appendingPathComponent(guide).path),
        ]
    }

    func setProblem(_ value: String?) async {
        guard value != problem else { return }
        problem = value
        if let value { trace("problem: \(value)") }
        await publishState(force: true)
    }

    func didChange(_ params: JSONValue) {
        guard let uri = params["textDocument"]?["uri"]?.stringValue, var doc = documents[uri],
              let changes = params["contentChanges"]?.arrayValue else { return }
        for change in changes {
            guard let text = change["text"]?.stringValue else { continue }
            doc.apply(range: change["range"].flatMap(Self.range), text: text)
        }
        documents[uri] = doc
    }

}
