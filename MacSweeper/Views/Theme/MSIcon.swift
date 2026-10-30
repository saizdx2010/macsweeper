import SwiftUI

/// Custom "Sweep Line" icon set from `design/figcraft`, loaded as `ms-<name>` template assets.
enum MSIcon: String, CaseIterable {
    // Navigation and actions
    case overview, scan, results, disk, history, help, settings, clean, done
    // Categories
    case browser, layers, chat, video, music, pen, gamepad, hammer, simulator, android
    case package, braces, code, `extension`, mug, containers, sparkle, folderClock = "folder-clock"
    case backup, snapshot, log, download, mail, paperclip, photo, type, question
    case trash, sleep, ghost, installer, cloudDown = "cloud-down"

    var assetName: String { "ms-\(rawValue)" }

    var image: Image { Image(assetName) }

    /// Shared tint so categories with the same icon also share a color.
    var tint: Color {
        switch self {
        case .browser, .mail: return Color(red: 0.23, green: 0.51, blue: 0.96)
        case .layers, .sleep: return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .chat, .paperclip: return Color(red: 0.93, green: 0.28, blue: 0.60)
        case .video, .trash: return Color(red: 0.94, green: 0.27, blue: 0.27)
        case .music: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .pen: return Color(red: 0.88, green: 0.11, blue: 0.28)
        case .gamepad: return Color(red: 0.39, green: 0.40, blue: 0.95)
        case .hammer: return Color(red: 0.06, green: 0.73, blue: 0.51)
        case .simulator: return Color(red: 0.08, green: 0.72, blue: 0.65)
        case .android: return Color(red: 0.40, green: 0.70, blue: 0.10)
        case .package: return Color(red: 0.98, green: 0.45, blue: 0.09)
        case .braces: return Color(red: 0.80, green: 0.60, blue: 0.03)
        case .code, .download: return Color(red: 0.05, green: 0.65, blue: 0.91)
        case .extension: return Color(red: 0.02, green: 0.71, blue: 0.83)
        case .mug: return Color(red: 0.85, green: 0.47, blue: 0.02)
        case .containers: return Color(red: 0.15, green: 0.39, blue: 0.92)
        case .sparkle: return Color(red: 0.66, green: 0.33, blue: 0.97)
        case .folderClock: return Color(red: 0.02, green: 0.59, blue: 0.41)
        case .backup: return Color(red: 0.39, green: 0.45, blue: 0.55)
        case .snapshot: return Color(red: 0.28, green: 0.33, blue: 0.41)
        case .log: return Color(red: 0.47, green: 0.44, blue: 0.42)
        case .photo: return Color(red: 0.96, green: 0.45, blue: 0.71)
        case .type, .question: return Color(red: 0.44, green: 0.44, blue: 0.48)
        case .ghost: return Color(red: 0.65, green: 0.55, blue: 0.98)
        case .installer: return Color(red: 0.05, green: 0.58, blue: 0.53)
        case .cloudDown: return Color(red: 0.13, green: 0.77, blue: 0.37)
        default: return MSTheme.accent
        }
    }

    /// Icon for a cleanup rule id from `cleanup-rules.json`; `nil` falls back to the rule's SF Symbol.
    static func forCategory(id: String) -> MSIcon? {
        if id.hasPrefix("browser_") { return .browser }
        return categoryIcons[id]
    }

    private static let categoryIcons: [String: MSIcon] = [
        "user_app_caches": .layers, "electron_app_caches": .layers,
        "slack_cache": .chat, "discord_cache": .chat, "messaging_app_caches": .chat,
        "zoom_cache": .video,
        "spotify_cache": .music, "itunes_podcast_cache": .music,
        "spotify_offline_storage": .cloudDown,
        "adobe_temp": .pen,
        "steam_caches": .gamepad,
        "xcode_derived_data": .hammer, "xcode_archives": .hammer,
        "xcode_ios_device_support": .hammer, "xcode_other_device_support": .hammer,
        "core_simulator_caches": .simulator, "simulator_unavailable_cleanup": .simulator,
        "simulator_runtimes": .simulator,
        "android_studio_avd": .android,
        "dev_node_modules": .package, "dev_npm_pnpm_yarn_caches": .package, "dev_bun_cache": .package,
        "dev_playwright_cypress": .package, "dev_gradle": .package, "dev_cocoapods": .package,
        "dev_go_caches": .package, "dev_maven_cache": .package, "dev_carthage_cache": .package,
        "dev_venvs": .braces, "dev_pip_cache": .braces, "dev_bundler_cache": .braces,
        "jetbrains_caches": .code,
        "editor_extension_caches": .extension,
        "homebrew_caches": .mug, "homebrew_cleanup": .mug,
        "docker_reclaim": .containers,
        "ai_model_caches": .sparkle,
        "dev_stale_build_artifacts": .folderClock, "dev_cargo_target": .folderClock,
        "ios_device_backups": .backup,
        "time_machine_snapshots": .snapshot,
        "user_logs": .log,
        "old_downloads": .download,
        "mail_downloads": .mail,
        "messages_attachments": .paperclip,
        "quicklook_thumbnails": .photo,
        "font_caches": .type,
        "safari_help_cache": .question,
        "empty_trash": .trash,
        "unused_apps": .sleep,
        "orphaned_app_leftovers": .ghost,
        "installer_leftovers": .installer,
    ]
}

/// Template icon sized like an SF Symbol at the given point size.
struct MSIconView: View {
    let icon: MSIcon
    var size: CGFloat = 16

    var body: some View {
        icon.image
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
