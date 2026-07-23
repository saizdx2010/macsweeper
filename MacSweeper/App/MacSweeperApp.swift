import SwiftUI

@main
struct MacSweeperApp: App {
    @StateObject private var auditLog = AuditLogService()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(auditLog)
        }
        .defaultSize(width: 720, height: 560)
        .windowResizability(.contentMinSize)
    }
}
