import Foundation

/// Opts a repository in: writes `.plan-complete.json`, and a starter plan when there is none.
public enum Setup {
    public static func enable(root: URL, writePlan: Bool = true) throws -> [String] {
        var created: [String] = []
        let config = Config.repoFile(in: root)
        if !FileManager.default.fileExists(atPath: config.path) {
            try Data(configTemplate.utf8).write(to: config)
            created.append(Config.fileName)
        }
        let guide = ((try? Config.load(root: root, globalFile: nil)) ?? Config()).guide
        let plan = root.appendingPathComponent(guide)
        if writePlan, guide.lowercased().hasSuffix(".md"), !FileManager.default.fileExists(atPath: plan.path) {
            try FileManager.default.createDirectory(at: plan.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(planTemplate.utf8).write(to: plan)
            created.append(guide)
        }
        return created
    }

    public static let settingsURL = "https://github.com/mheh/plan-complete#settings"

    /// Writes the global file, with the model server fields commented out, when there is none.
    public static func createGlobalFile(at url: URL = Config.globalFile) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(globalTemplate.utf8).write(to: url)
    }

    public static var globalTemplate: String {
        template(header: [
            "// plan-complete settings for every repository: where your model server is.",
            "// A repository's .plan-complete.json overrides these. Comments and trailing commas are fine.",
        ], groups: [("The model server. The defaults fit `llama-server --port 8012`.", templateFields[1].keys),
                    templateFields[2]])
    }

    /// Every field commented out at its default, in the order of `templateFields`.
    public static var configTemplate: String {
        template(header: [
            "// This file turns plan-complete on for this repository. Every field is optional;",
            "// the lines below show the defaults. Comments and trailing commas are fine.",
        ], groups: templateFields)
    }

    static func template(header: [String], groups: [(note: String, keys: [String])]) -> String {
        let defaults = (try? JSONValue.decode(JSONEncoder().encode(Config())))?.objectValue ?? [:]
        func line(_ key: String) -> String {
            let value = defaults[key] ?? .null
            return "  // \"\(key)\": \(String(decoding: (try? value.encoded(spaced: true)) ?? Data(), as: UTF8.self)),"
        }
        var lines = header + ["// \(settingsURL)", "{"]
        for group in groups {
            lines.append("")
            lines.append("  // \(group.note)")
            lines.append(contentsOf: group.keys.map(line))
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    static let templateFields: [(note: String, keys: [String])] = [
        ("The plan: one Markdown file, or a folder of them.", ["guide", "guideTokenBudget"]),
        ("The model server. These usually go in the global file, \(Config.globalFileHint).",
         ["baseURL", "provider", "model", "apiKey"]),
        ("The size of a completion, and of the code around the cursor.",
         ["maxTokens", "maxLines", "prefixLines", "suffixLines", "timeoutMs", "debounceMs"]),
        ("What goes into the prompt.", ["useGuide", "useScope", "context"]),
        ("How plan sections are ranked. Subject to change between versions.", ["scoring"]),
    ]

    public static let planTemplate = """
    # Plan

    <!--
    plan-complete steers inline completions with this file. Text in HTML comments is not read.

    Write one "## " section for each step, and name the file it is about. Put exact signatures,
    names, defaults and rules in `code spans`. For example:

    ## Step 1: ResponseCache in Sources/Net/Cache.swift

    `actor ResponseCache` holds at most `capacity` items; the default capacity is 100.
    - `func store(_ data: Data, for key: URL) async` inserts, then calls `evictIfNeeded()`.
    - No force unwraps.
    -->

    """
}
