import Foundation
import PlanCompleteCore

extension LSPServer {
    func inlineCompletion(id: JSONValue, params: JSONValue) {
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
        let editorContext = Self.editorContext(params)
        if !editorContext.symbols.isEmpty { trace("symbols \(id) \(editorContext.symbols)") }

        pending.removeValue(forKey: uri)?.task.cancel()
        let snapshot = document
        let finalCursor = cursor
        let rangeStart = start
        let original = (line, character)
        let task = Task { [weak self] in
            guard let self else { return }
            let config = await engine.config
            let debounce = config.debounceMs
            var items: [JSONValue] = []
            var failure: String?
            var answered = false
            do {
                if debounce > 0 { try await Task.sleep(for: .milliseconds(debounce)) }
                let completion = try await engine.complete(document: snapshot, line: finalCursor.0,
                                                           utf16Column: finalCursor.1, editorContext: editorContext)
                answered = true
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
                failure = modelFailure(error, config: config)
            }
            if failure != nil || answered { await self.setProblem(failure) }
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

    static func editorContext(_ params: JSONValue) -> EditorContext {
        let files = (params["extraContext"]?.arrayValue ?? []).compactMap { item -> ExtraFile? in
            guard let path = item["path"]?.stringValue, let text = item["text"]?.stringValue else { return nil }
            return ExtraFile(path: path, text: text)
        }
        let symbols = (params["symbolPath"]?.arrayValue ?? []).compactMap { item -> SymbolPath.Symbol? in
            guard let name = item["name"]?.stringValue, let kind = item["kind"]?.intValue else { return nil }
            return SymbolPath.Symbol(name: name, lspKind: kind)
        }
        return EditorContext(files: files, symbols: SymbolPath(symbols))
    }

    func finish(uri: String, id: JSONValue, cancelled: Bool) async {
        tasksByID[id] = nil
        if pending[uri]?.id == id { pending[uri] = nil }
        if cancelled { await reply(id, result: ["items": []]) }
    }

    func cancelAll() {
        for (_, entry) in pending { entry.task.cancel() }
    }
}
