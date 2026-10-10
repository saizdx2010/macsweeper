import Foundation

struct TroubleshootingGuide: Decodable, Identifiable, Equatable {
    let id: String
    let symptom: String
    let whenItHelps: String
    let whenItWontHelp: String
    let commands: [String]
    let needsAdmin: Bool
}

/// Read-only help content. MacSweeper never runs these commands.
enum TroubleshootingGuides {
    private struct File: Decodable { let guides: [TroubleshootingGuide] }

    static func decode(_ data: Data) throws -> [TroubleshootingGuide] {
        try JSONDecoder().decode(File.self, from: data).guides
    }

    static func load(bundle: Bundle = .main) -> [TroubleshootingGuide] {
        guard let url = bundle.url(forResource: "troubleshooting-guides", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let guides = try? decode(data) else { return [] }
        return guides
    }
}
