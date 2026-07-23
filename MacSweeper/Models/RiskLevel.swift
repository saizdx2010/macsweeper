import SwiftUI

enum RiskLevel: String, Codable, CaseIterable, Identifiable {
    case safe
    case moderate
    case risky
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safe: return "Safe"
        case .moderate: return "Moderate"
        case .risky: return "Risky"
        case .manual: return "Manual"
        }
    }

    /// Safe categories are selected by default; others are not.
    var isSelectedByDefault: Bool {
        self == .safe
    }

    var color: Color {
        switch self {
        case .safe:
            return .secondary
        case .moderate:
            return .orange
        case .risky:
            return .red.opacity(0.8)
        case .manual:
            return .secondary
        }
    }

    var guidanceLine: String {
        switch self {
        case .safe:
            return "Selected by default"
        case .moderate:
            return "Review before cleaning"
        case .risky:
            return "Review carefully before cleaning"
        case .manual:
            return "Guide only"
        }
    }
}
