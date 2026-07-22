import Foundation

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
}
