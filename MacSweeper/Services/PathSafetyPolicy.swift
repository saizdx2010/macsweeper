import Foundation

/// Single catalog for discovery skips and trash allowlisting.
///
/// Scan discovery and cleanup historically maintained separate prefix lists;
/// keep both policies here so exclusions cannot drift apart unnoticed.
enum PathSafetyPolicy {
    /// Relative home prefixes never entered during `find_named_dirs` walks.
    static let discoverySkipPrefixes: [String] = [
        "Library",
        "Documents",
        "Pictures",
        "Music",
        "Movies",
        ".Trash",
    ]

    /// Relative home paths that must never be trashed (and anything under them).
    static let trashProtectedPrefixes: [String] = [
        "Documents",
        "Desktop",
        "Pictures",
        "Music",
        "Movies",
        // Credential / secrets roots
        ".ssh",
        ".gnupg",
        ".aws",
        ".config",
        ".kube",
        ".docker",
        // Sensitive Library data
        "Library/Keychains",
        "Library/Mail",
        "Library/Messages",
        "Library/Suggestions",
        "Library/Containers/com.apple.Safari",
        "Library/Safari",
        "Library/Accounts",
        "Library/Cookies",
        "Library/IdentityServices",
        "Library/Calendars",
        "Library/Reminders",
        "Library/Shortcuts",
        "Library/PersonalizationPortrait",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/CallHistoryTransactions",
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/1Password",
        "Library/Application Support/com.1password.1password",
        "Library/Application Support/Bitwarden",
        "Library/Application Support/com.bitwarden.desktop",
        // Browser profile credential stores (caches live under different rule paths)
        "Library/Application Support/Google/Chrome/Default/Login Data",
        "Library/Application Support/Google/Chrome/Default/Cookies",
        "Library/Application Support/Google/Chrome/Default/Web Data",
        "Library/Application Support/Microsoft Edge/Default/Login Data",
        "Library/Application Support/Microsoft Edge/Default/Cookies",
        "Library/Application Support/Microsoft Edge/Default/Web Data",
        "Library/Application Support/BraveSoftware/Brave-Browser/Default/Login Data",
        "Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies",
        "Library/Application Support/BraveSoftware/Brave-Browser/Default/Web Data",
        "Library/Application Support/Firefox/Profiles",
    ]

    /// Dev-mode discovery targets allowed under otherwise-protected roots (Documents/Desktop).
    static let allowedDevCleanupDirectoryNames: Set<String> = [
        "node_modules",
        ".venv",
        "venv",
        "target",
        ".gradle",
        "Pods",
    ]

    /// Whether a path may be moved to Trash (home-only allowlist + protected prefixes).
    static func isAllowedToTrash(_ path: String, homeDirectory: String) -> Bool {
        // Resolve symlinks so a link under an allowed folder cannot escape into a protected root.
        let standardized = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let home = URL(fileURLWithPath: homeDirectory).resolvingSymlinksInPath().path
        guard standardized.hasPrefix(home + "/") || standardized == home + "/.Trash" else {
            return false
        }
        guard standardized != home else { return false }

        // Never move the Trash folder itself via trashItem.
        if standardized == home + "/.Trash" { return false }

        let relative = String(standardized.dropFirst(home.count + 1))
        if relative == "Library" { return false }

        let lastComponent = (relative as NSString).lastPathComponent
        let isDevCleanupDir = allowedDevCleanupDirectoryNames.contains(lastComponent)

        for prefix in trashProtectedPrefixes {
            if relative == prefix || relative.hasPrefix(prefix + "/") {
                // Allow only named Dev cleanup dirs under Documents / Desktop project roots.
                if isDevCleanupDir, prefix == "Documents" || prefix == "Desktop" {
                    return true
                }
                return false
            }
        }
        return true
    }

    /// Whether discovery walks should skip this path (and not report matches under it).
    static func isProtectedDiscoveryPath(_ path: String, homeDirectory: String) -> Bool {
        let home = (homeDirectory as NSString).standardizingPath
        let standardized = (path as NSString).standardizingPath
        guard isPathUnderHome(standardized, homeDirectory: home) else { return true }
        guard standardized != home else { return true }

        let relative = String(standardized.dropFirst(home.count + 1))
        for prefix in discoverySkipPrefixes {
            if relative == prefix || relative.hasPrefix(prefix + "/") {
                // Allow Documents/GitHub specifically (it's a configured root).
                if prefix == "Documents",
                   relative == "Documents/GitHub" || relative.hasPrefix("Documents/GitHub/") {
                    return false
                }
                return true
            }
        }
        return false
    }

    static func isPathUnderHome(_ path: String, homeDirectory: String) -> Bool {
        let home = URL(fileURLWithPath: homeDirectory).resolvingSymlinksInPath().path
        let standardized = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return standardized == home || standardized.hasPrefix(home + "/")
    }
}
