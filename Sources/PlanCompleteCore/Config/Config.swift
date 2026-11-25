import Foundation

public enum ProviderKind: String, Sendable, Codable {
    case llamaInfill = "llama-infill"
    case openAIFIM = "openai-fim"
}

public struct Config: Sendable, Equatable, Codable {
    public var baseURL: String = "http://127.0.0.1:8012"
    public var provider: ProviderKind = .llamaInfill
    public var model: String = "default"
    public var apiKey: String? = nil
    public var guide: String = Config.defaultGuide
    public var guideTokenBudget: Int = 1200
    public var maxTokens: Int = 64
    public var maxLines: Int = 12
    public var prefixLines: Int = 80
    public var suffixLines: Int = 40
    public var timeoutMs: Int = 4000
    public var debounceMs: Int = 60
    public var useGuide: Bool = true
    public var useScope: Bool = true
    public var context = Context()
    public var scoring = Scoring()

    /// What the editor gathers from the real language server.
    public struct Context: Sendable, Equatable, Codable {
        public var signature = true
        public var timeoutMs = 100
        public var tokenBudget = 300
        public init() {}
    }

    /// Points that a plan section earns. Subject to change between versions.
    public struct Scoring: Sendable, Equatable, Codable {
        public var glob = 10.0
        public var file = 8.0
        public var symbol = 4.0
        public var codeSpan = 2.0
        public var heading = 2.0
        public var words = 3.0
        public init() {}
    }

    public init() {}

    public var redacted: Config {
        var copy = self
        if copy.apiKey != nil { copy.apiKey = "***" }
        return copy
    }
}

extension Config {
    public static let fileName = ".plan-complete.json"
    public static let defaultGuide = "PLAN.md"
    public static let globalFileHint = "~/.config/plan-complete/config.json"
    static let guideKey = "guide"

    public static func repoFile(in root: URL) -> URL { root.appendingPathComponent(fileName) }

    public static var globalFile: URL {
        let env = ProcessInfo.processInfo.environment
        var folder = env["XDG_CONFIG_HOME"]
        #if os(Windows)
        folder = folder ?? env["APPDATA"]
        #endif
        let base = folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        return base.appendingPathComponent("plan-complete/config.json")
    }

    /// Defaults, the global file, then `<root>/.plan-complete.json`. Each layer sets only the fields it names.
    /// Only the repo file can name the plan; a `guide` anywhere else is dropped.
    public static func load(root: URL, globalFile: URL? = Config.globalFile) throws -> Config {
        var config = Config()
        if let globalFile, let data = try? Data(contentsOf: globalFile) {
            config = try config.merged(with: try JSONValue.decode(jsonc: data).removing(guideKey))
        }
        if let data = try? Data(contentsOf: repoFile(in: root)) {
            config = try config.merged(with: try JSONValue.decode(jsonc: data))
        }
        config.guide = safeGuide(config.guide)
        return config
    }

    public func applyingEditor(_ overrides: JSONValue?) throws -> Config {
        var config = try merged(with: overrides?.removing(Self.guideKey))
        config.guide = guide
        return config
    }

    public func merged(with overrides: JSONValue?) throws -> Config {
        guard let overrides, overrides.objectValue != nil else { return self }
        let base = try JSONValue.decode(JSONEncoder().encode(self))
        return try JSONDecoder().decode(Config.self, from: base.merging(overrides).encoded())
    }

    public static func safeGuide(_ value: String) -> String {
        let path = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "/")
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains(":"),
              !parts.contains("..") else { return defaultGuide }
        return path
    }
}
