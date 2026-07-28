import AppKit
import Foundation

/// Reveals a filesystem path in Finder.
enum FinderReveal {
    static func reveal(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
