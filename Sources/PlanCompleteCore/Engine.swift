import Foundation

public struct Completion: Sendable, Equatable {
    public var text: String
    public var sources: [String]
    public var fromCache: Bool
    public var raw: String
}

public actor Engine {
    public private(set) var config: Config
    public let root: URL
    private var provider: any CompletionProvider
    private var chunks: [GuideChunk] = []
    private var guideSignature: [String: Date] = [:]
    private var lastGuideCheck: Date = .distantPast
    private var planState: PlanState = .noConfig
    private var lastStateCheck: Date = .distantPast
    public private(set) var enabled = true
    /// Only `probe --no-guide` sets it.
    public var bypassPlanRule = false

    public func setBypassPlanRule(_ value: Bool) { bypassPlanRule = value }

    public func setEnabled(_ value: Bool) {
        enabled = value
        lastStateCheck = .distantPast
    }
    private var cache = LRUCache<String, Entry>(capacity: 256)
    private var recent: [Entry] = []

    struct Entry: Sendable {
        var path: String
        var prefix: String
        var suffix: String
        var completion: Completion
    }

    public init(root: URL, config: Config, provider: (any CompletionProvider)? = nil) {
        self.root = root
        self.config = config
        self.provider = provider ?? makeProvider(config)
    }

    public func update(config: Config, provider: (any CompletionProvider)? = nil) {
        self.config = config
        self.provider = provider ?? makeProvider(config)
        resetCaches()
        lastGuideCheck = .distantPast
        lastStateCheck = .distantPast
        guideSignature = [:]
    }

    public func state(now: Date = Date()) -> PlanState {
        guard now.timeIntervalSince(lastStateCheck) >= 1 else { return planState }
        lastStateCheck = now
        planState = PlanState.check(root: root, guide: config.guide, enabled: enabled)
        return planState
    }

    /// Reloads when a guide file changed, checking at most once a second.
    public func guide(now: Date = Date()) -> [GuideChunk] {
        guard now.timeIntervalSince(lastGuideCheck) >= 1 else { return chunks }
        lastGuideCheck = now
        let location = root.appendingPathComponent(config.guide)
        var signature: [String: Date] = [:]
        for url in Guide.markdownFiles(at: location) {
            signature[url.path] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
        }
        if signature != guideSignature {
            guideSignature = signature
            chunks = Guide.load(path: location, root: root)
            resetCaches()
        }
        return chunks
    }

    public struct Prepared: Sendable {
        public var request: CompletionRequest
        public var context: TextDocument.Context
        public var guide: [GuideChunk]
    }

    /// `editorContext` is what the editor got from the real language server, for example signature help.
    public func prepare(document: TextDocument, line: Int, utf16Column: Int, editorContext: [ExtraFile] = []) -> Prepared {
        let editorContext = Self.trimmed(editorContext, tokens: config.context.tokenBudget)
        let context = document.context(line: line, utf16Column: utf16Column,
                                       prefixLines: config.prefixLines, suffixLines: config.suffixLines)
        let path = relativePath(of: URL(fileURLWithPath: document.path), to: root)
        var selected: [GuideChunk] = []
        if config.useGuide {
            let window = context.window + "\n" + context.scope.outline.joined(separator: "\n")
                + "\n" + editorContext.map(\.text).joined(separator: "\n")
            selected = GuideSelector(budget: config.guideTokenBudget, scoring: config.scoring)
                .select(chunks: guide(), path: path, window: window)
        }
        var extras = Self.extras(from: selected)
        if config.useScope {
            if editorContext.isEmpty, let scope = context.scope.summary(path: path) { extras.append(scope) }
            extras.append(contentsOf: editorContext)
        }
        var prefix = context.prefix
        var suffix = context.suffix
        let typed = context.linePrefix.trimmingCharacters(in: .whitespaces)
        if Postprocess.isCommentLine(typed) {
            suffix = suffix.split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: false)
                .prefix(3).joined(separator: "\n")
        }
        if context.linePrefix.contains(where: { $0 != " " && $0 != "\t" }) {
            while prefix.last == " " { prefix.removeLast() }
            if suffix.hasPrefix("\n") {
                let rest = suffix.drop { $0 == "\n" || $0 == " " || $0 == "\t" }
                suffix = "\n" + rest
            }
        }
        let request = CompletionRequest(path: path, prefix: prefix, suffix: suffix,
                                        extras: extras, maxTokens: config.maxTokens)
        return Prepared(request: request, context: context, guide: selected)
    }

    /// The first items win; the one that crosses the budget is cut.
    static func trimmed(_ extras: [ExtraFile], tokens: Int) -> [ExtraFile] {
        var left = max(0, tokens) * 4
        var kept: [ExtraFile] = []
        for var extra in extras where left > 0 {
            if extra.text.utf8.count > left { extra.text = String(extra.text.prefix(left)) }
            left -= extra.text.utf8.count
            kept.append(extra)
        }
        return kept
    }

    /// One extra file for each guide file; the best chunks come last, nearest the cursor.
    static func extras(from chunks: [GuideChunk]) -> [ExtraFile] {
        var order: [String] = []
        var texts: [String: [String]] = [:]
        for chunk in chunks.reversed() {
            if texts[chunk.source] == nil { order.append(chunk.source) }
            texts[chunk.source, default: []].append(chunk.text)
        }
        return order.map { ExtraFile(path: $0, text: texts[$0, default: []].joined(separator: "\n\n") + "\n") }
    }

    public func complete(document: TextDocument, line: Int, utf16Column: Int,
                         editorContext: [ExtraFile] = []) async throws -> Completion {
        if !bypassPlanRule, !state().isOn { return Completion(text: "", sources: [], fromCache: false, raw: "") }
        let prepared = prepare(document: document, line: line, utf16Column: utf16Column, editorContext: editorContext)
        let request = prepared.request
        let key = Self.cacheKey(request)
        if var hit = cache.value(for: key) {
            hit.completion.fromCache = true
            return hit.completion
        }
        if let typed = typeahead(request) { return typed }

        var raw = try await provider.complete(request)
        try Task.checkCancellation()
        var text = Postprocess.clean(raw, linePrefix: prepared.context.linePrefix, suffix: prepared.context.suffix,
                                     maxLines: config.maxLines)
        // On a started comment line the model often ends the line at once; without a suffix it writes it.
        if text.isEmpty, Postprocess.isCommentLine(prepared.context.linePrefix.trimmingCharacters(in: .whitespaces)) {
            var retry = request
            retry.suffix = ""
            raw = try await provider.complete(retry)
            try Task.checkCancellation()
            text = Postprocess.clean(raw, linePrefix: prepared.context.linePrefix, suffix: prepared.context.suffix,
                                     maxLines: config.maxLines)
        }
        let guideSources = Set(prepared.guide.map(\.source))
        let sources = prepared.guide.map { chunk in chunk.heading.map { "\(chunk.source)#\($0)" } ?? chunk.source }
            + request.extras.map(\.path).filter { !guideSources.contains($0) }
        let completion = Completion(text: text, sources: sources, fromCache: false, raw: raw)
        let entry = Entry(path: request.path, prefix: request.prefix, suffix: request.suffix, completion: completion)
        cache.set(entry, for: key)
        recent.append(entry)
        if recent.count > 8 { recent.removeFirst() }
        return completion
    }

    /// The user typed the start of an earlier completion: the rest of it still applies.
    func typeahead(_ request: CompletionRequest) -> Completion? {
        for entry in recent.reversed() where entry.path == request.path && entry.suffix == request.suffix {
            guard request.prefix.count > entry.prefix.count, request.prefix.hasPrefix(entry.prefix) else { continue }
            let typed = String(request.prefix.dropFirst(entry.prefix.count))
            guard entry.completion.text.count > typed.count, entry.completion.text.hasPrefix(typed) else { continue }
            var completion = entry.completion
            completion.text = String(entry.completion.text.dropFirst(typed.count))
            completion.fromCache = true
            return completion
        }
        return nil
    }

    private func resetCaches() {
        cache.removeAll()
        recent.removeAll()
    }

    static func cacheKey(_ request: CompletionRequest) -> String {
        let extras = request.extras.map { "\($0.path)\u{1}\($0.text)" }.joined(separator: "\u{2}")
        return "\(request.path)\u{0}\(request.prefix.suffix(600))\u{0}\(request.suffix.prefix(300))\u{0}\(extras.hashValue)"
    }
}
