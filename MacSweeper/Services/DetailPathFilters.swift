import Foundation

/// Age / size filters for Detail list categories (Downloads, Mail, discovery).
enum DetailAgeFilter: String, CaseIterable, Identifiable, Sendable {
    case any
    case older14
    case older30
    case older90

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Any age"
        case .older14: return ">14 days"
        case .older30: return ">30 days"
        case .older90: return ">90 days"
        }
    }

    func matches(_ date: Date?, now: Date = Date()) -> Bool {
        switch self {
        case .any:
            return true
        case .older14:
            guard let date else { return false }
            return date < now.addingTimeInterval(-14 * 24 * 60 * 60)
        case .older30:
            guard let date else { return false }
            return date < now.addingTimeInterval(-30 * 24 * 60 * 60)
        case .older90:
            guard let date else { return false }
            return date < now.addingTimeInterval(-90 * 24 * 60 * 60)
        }
    }
}

enum DetailSizeFilter: String, CaseIterable, Identifiable, Sendable {
    case any
    case over100MB
    case over1GB

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Any size"
        case .over100MB: return ">100 MB"
        case .over1GB: return ">1 GB"
        }
    }

    func matches(_ bytes: Int64) -> Bool {
        switch self {
        case .any: return true
        case .over100MB: return bytes >= 100_000_000
        case .over1GB: return bytes >= 1_000_000_000
        }
    }
}

extension DetailPathQuery {
    static func matchesFilters(
        _ item: ScannedPath,
        age: DetailAgeFilter,
        size: DetailSizeFilter,
        now: Date = Date()
    ) -> Bool {
        age.matches(item.contentModificationDate, now: now) && size.matches(item.byteCount)
    }
}
