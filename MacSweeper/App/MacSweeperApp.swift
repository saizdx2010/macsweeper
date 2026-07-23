import SwiftUI

@main
struct MacSweeperApp: App {
    @StateObject private var auditLog = AuditLogService()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(auditLog)
                .environmentObject(settings)
                .tint(MSTheme.accent)
        }
        .defaultSize(width: 720, height: 560)
        .windowResizability(.contentMinSize)
    }
}
