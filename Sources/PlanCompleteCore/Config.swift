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
    public var guide: String = "PLAN.md"
    public var guideTokenBudget: Int = 1200
    public var maxTokens: Int = 64
    public var maxLines: Int = 12
    public var prefixLines: Int = 80
    public var suffixLines: Int = 40
    public var timeoutMs: Int = 4000
    public var debounceMs: Int = 60
    public var useGuide: Bool = true
    public var useScope: Bool = true

    public static let fileName = ".plan-complete.json"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? d.baseURL
        provider = try c.decodeIfPresent(ProviderKind.self, forKey: .provider) ?? d.provider
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        guide = try c.decodeIfPresent(String.self, forKey: .guide) ?? d.guide
        guideTokenBudget = try c.decodeIfPresent(Int.self, forKey: .guideTokenBudget) ?? d.guideTokenBudget
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? d.maxTokens
        maxLines = try c.decodeIfPresent(Int.self, forKey: .maxLines) ?? d.maxLines
        prefixLines = try c.decodeIfPresent(Int.self, forKey: .prefixLines) ?? d.prefixLines
        suffixLines = try c.decodeIfPresent(Int.self, forKey: .suffixLines) ?? d.suffixLines
        timeoutMs = try c.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? d.timeoutMs
        debounceMs = try c.decodeIfPresent(Int.self, forKey: .debounceMs) ?? d.debounceMs
        useGuide = try c.decodeIfPresent(Bool.self, forKey: .useGuide) ?? d.useGuide
        useScope = try c.decodeIfPresent(Bool.self, forKey: .useScope) ?? d.useScope
    }

    /// Defaults, then the global file, then `<root>/.plan-complete.json`. Each file sets only the fields it names.
    public static func load(root: URL, globalFile: URL? = Config.globalFile) throws -> Config {
        var config = Config()
        for url in [globalFile, root.appendingPathComponent(fileName)].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url) else { continue }
            config = try config.merged(with: try JSONValue.decode(data))
        }
        return config
    }

    /// `$XDG_CONFIG_HOME/plan-complete/config.json`, or `~/.config/plan-complete/config.json`.
    public static var globalFile: URL {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        return base.appendingPathComponent("plan-complete/config.json")
    }

    public func merged(with overrides: JSONValue?) throws -> Config {
        guard let overrides, case .object(var fields) = overrides else { return self }
        let base = try JSONValue.decode(JSONEncoder().encode(self))
        guard case .object(let baseFields) = base else { return self }
        fields = baseFields.merging(fields.filter { $0.value != .null }) { _, new in new }
        return try JSONDecoder().decode(Config.self, from: JSONValue.object(fields).encoded())
    }
}
