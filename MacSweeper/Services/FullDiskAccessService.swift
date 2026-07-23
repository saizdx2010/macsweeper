import AppKit
import Foundation

/// Detects Full Disk Access and opens System Settings when needed.
enum FullDiskAccessService {
    /// Best-effort check: try listing a TCC-protected user folder.
    static func isGranted() -> Bool {
        let candidates = [
            NSHomeDirectory() + "/Library/Mail",
            NSHomeDirectory() + "/Library/Safari",
            NSHomeDirectory() + "/Library/Caches/CloudKit",
        ]
        let fm = FileManager.default
        for path in candidates where fm.fileExists(atPath: path) {
            do {
                _ = try fm.contentsOfDirectory(atPath: path)
                return true
            } catch {
                return false
            }
        }
        // Nothing protected to probe — assume granted so we don't block needlessly.
        return true
    }

    static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
