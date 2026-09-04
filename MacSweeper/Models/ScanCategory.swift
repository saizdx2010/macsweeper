import Foundation

/// Special cleanup behaviors beyond “move path to Trash”.
enum CleanupAction: String, Codable, Hashable {
    case moveToTrash = "move_to_trash"
    case emptyTrash = "empty_trash"
}

/// How the scan engine locates paths for a category.
enum ScanStrategy: String, Codable, Hashable {
    case fixed
    case findNamedDirs = "find_named_dirs"
    /// Immediate children of each configured directory (e.g. Downloads).
    case listChildren = "list_children"
    /// App bundles in the configured roots (e.g. /Applications) unused for `min_age_days`.
    case unusedApps = "unused_apps"
}

/// A cleanup rule loaded from `cleanup-rules.json`.
struct ScanCategory: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let paths: [String]
    let risk: RiskLevel
    let description: String
    /// Defaults to move-to-Trash when omitted from JSON.
    var action: CleanupAction = .moveToTrash
    /// `"dev"` marks Dev-section items; `nil` = core.
    var group: String?
    /// Defaults to fixed path measurement when omitted.
    var scan: ScanStrategy = .fixed
    /// Directory names to find when `scan == .findNamedDirs`.
    var findNames: [String]?
    /// Max walk depth for discovery (from each root). Defaults to 6.
    var maxDepth: Int?
    /// Minimum days since last use for `scan == .unusedApps`. Defaults to 30.
    var minAgeDays: Int?
    /// Shell command shown for Manual guidance (copy to clipboard).
    var guideCommand: String?
    /// Presence-only guidance: never measured (size would double-count or mislead).
    var guideOnly: Bool = false
    /// Optional SF Symbol from JSON; falls back to `folder` when omitted.
    var icon: String?

    /// Whether this category belongs in the Dev results section.
    var isDevGroup: Bool { group == "dev" }

    /// SF Symbol used in results, detail, and clean summary rows.
    var sfSymbolName: String {
        if let icon, !icon.isEmpty { return icon }
        return "folder"
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, paths, risk, description, action, group, scan, icon
        case findNames = "find_names"
        case maxDepth = "max_depth"
        case minAgeDays = "min_age_days"
        case guideCommand = "guide_command"
        case guideOnly = "guide_only"
    }

    init(
        id: String,
        label: String,
        paths: [String],
        risk: RiskLevel,
        description: String,
        action: CleanupAction = .moveToTrash,
        group: String? = nil,
        scan: ScanStrategy = .fixed,
        findNames: [String]? = nil,
        maxDepth: Int? = nil,
        minAgeDays: Int? = nil,
        guideCommand: String? = nil,
        guideOnly: Bool = false,
        icon: String? = nil
    ) {
        self.id = id
        self.label = label
        self.paths = paths
        self.risk = risk
        self.description = description
        self.action = action
        self.group = group
        self.scan = scan
        self.findNames = findNames
        self.maxDepth = maxDepth
        self.minAgeDays = minAgeDays
        self.guideCommand = guideCommand
        self.guideOnly = guideOnly
        self.icon = icon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        paths = try container.decode([String].self, forKey: .paths)
        risk = try container.decode(RiskLevel.self, forKey: .risk)
        description = try container.decode(String.self, forKey: .description)
        action = try container.decodeIfPresent(CleanupAction.self, forKey: .action) ?? .moveToTrash
        group = try container.decodeIfPresent(String.self, forKey: .group)
        scan = try container.decodeIfPresent(ScanStrategy.self, forKey: .scan) ?? .fixed
        findNames = try container.decodeIfPresent([String].self, forKey: .findNames)
        maxDepth = try container.decodeIfPresent(Int.self, forKey: .maxDepth)
        minAgeDays = try container.decodeIfPresent(Int.self, forKey: .minAgeDays)
        guideCommand = try container.decodeIfPresent(String.self, forKey: .guideCommand)
        guideOnly = try container.decodeIfPresent(Bool.self, forKey: .guideOnly) ?? false
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
    }
}
