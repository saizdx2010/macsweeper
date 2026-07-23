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
    /// Shell command shown for Manual guidance (copy to clipboard).
    var guideCommand: String?

    /// Whether this category belongs in the Dev results section.
    var isDevGroup: Bool { group == "dev" }

    /// SF Symbol used in results, detail, and clean summary rows.
    var sfSymbolName: String {
        switch id {
        case "browser_chrome_cache", "browser_safari_cache", "browser_firefox_cache", "browser_edge_cache":
            return "globe"
        case "user_app_caches", "font_caches", "quicklook_thumbnails", "itunes_podcast_cache", "core_simulator_caches",
             "slack_cache", "zoom_cache", "discord_cache", "spotify_cache", "adobe_temp", "electron_app_caches":
            return "internaldrive"
        case "user_logs":
            return "doc.text"
        case "xcode_derived_data", "xcode_archives", "xcode_ios_device_support":
            return "hammer"
        case "mail_downloads", "old_downloads":
            return "arrow.down.circle"
        case "empty_trash":
            return "trash"
        case "dev_node_modules", "dev_npm_pnpm_yarn_caches":
            return "shippingbox"
        case "dev_venvs", "dev_pip_cache":
            return "chevron.left.forwardslash.chevron.right"
        case "dev_cargo_target", "dev_gradle", "dev_cocoapods":
            return "hammer"
        case "homebrew_caches", "homebrew_cleanup":
            return "mug"
        case "docker_reclaim":
            return "shippingbox"
        default:
            return "folder"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, paths, risk, description, action, group, scan
        case findNames = "find_names"
        case maxDepth = "max_depth"
        case guideCommand = "guide_command"
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
        guideCommand: String? = nil
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
        self.guideCommand = guideCommand
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
        guideCommand = try container.decodeIfPresent(String.self, forKey: .guideCommand)
    }
}
