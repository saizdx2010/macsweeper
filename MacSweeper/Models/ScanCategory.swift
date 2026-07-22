import Foundation

/// A cleanup rule loaded from `cleanup-rules.json`.
struct ScanCategory: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let paths: [String]
    let risk: RiskLevel
    let description: String
}
