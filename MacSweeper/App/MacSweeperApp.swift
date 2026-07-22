import SwiftUI

@main
struct MacSweeperApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .defaultSize(width: 480, height: 420)
    }
}
