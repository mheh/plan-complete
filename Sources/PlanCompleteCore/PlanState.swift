import Foundation

/// Whether the server answers in a repository, and why not.
public enum PlanState: Sendable, Equatable {
    case on(guide: String)
    case noConfig
    case noPlan(guide: String)
    case disabled

    public var isOn: Bool { if case .on = self { return true }; return false }

    public var reason: String {
        switch self {
        case .on(let guide): return guide
        case .noConfig: return "no \(Config.fileName)"
        case .noPlan(let guide): return "no \(guide)"
        case .disabled: return "turned off"
        }
    }

    /// Needs `<root>/.plan-complete.json`, then the plan it names (`PLAN.md` by default):
    /// a file, or a folder with at least one `.md` file.
    public static func check(root: URL, guide: String, enabled: Bool = true) -> PlanState {
        guard enabled else { return .disabled }
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.appendingPathComponent(Config.fileName).path) else { return .noConfig }
        let location = root.appendingPathComponent(guide)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: location.path, isDirectory: &isDirectory) else { return .noPlan(guide: guide) }
        if isDirectory.boolValue, Guide.markdownFiles(at: location).isEmpty { return .noPlan(guide: guide) }
        return .on(guide: guide)
    }
}
