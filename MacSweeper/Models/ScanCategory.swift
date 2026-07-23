import Foundation

/// Special cleanup behaviors beyond “move path to Trash”.
enum CleanupAction: String, Codable, Hashable {
    case moveToTrash = "move_to_trash"
    case emptyTrash = "empty_trash"
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

    private enum CodingKeys: String, CodingKey {
        case id, label, paths, risk, description, action
    }

    init(
        id: String,
        label: String,
        paths: [String],
        risk: RiskLevel,
        description: String,
        action: CleanupAction = .moveToTrash
    ) {
        self.id = id
        self.label = label
        self.paths = paths
        self.risk = risk
        self.description = description
        self.action = action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        paths = try container.decode([String].self, forKey: .paths)
        risk = try container.decode(RiskLevel.self, forKey: .risk)
        description = try container.decode(String.self, forKey: .description)
        action = try container.decodeIfPresent(CleanupAction.self, forKey: .action) ?? .moveToTrash
    }
}
