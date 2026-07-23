import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var auditLog: AuditLogService
    @Binding var path: NavigationPath
    @AppStorage("includeDevMode") private var includeDevMode = false

    var body: some View {
        ZStack {
            StageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: MSTheme.sectionSpacing) {
                    MSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SCAN")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Toggle("Include Dev mode by default", isOn: $includeDevMode)
                                .toggleStyle(.switch)

                            Text("When on, scans also look for node_modules, virtualenvs, and other Dev caches.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    MSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("DEV FOLDERS")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text("Extra project roots beyond the built-in list (\(AppSettings.defaultDevRootPaths.joined(separator: ", "))).")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if settings.customDevRoots.isEmpty {
                                Text("No custom folders yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(settings.customDevRoots) { root in
                                    HStack {
                                        Text(displayPath(root.path))
                                            .font(.system(.body, design: .monospaced))
                                            .lineLimit(2)
                                            .textSelection(.enabled)
                                        Spacer()
                                        Button("Remove") {
                                            settings.removeDevRoot(id: root.id)
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                    if root.id != settings.customDevRoots.last?.id {
                                        Divider().opacity(0.4)
                                    }
                                }
                            }

                            Button("Add folder…") {
                                settings.addDevRootInteractively()
                            }
                        }
                    }

                    MSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("HISTORY")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Toggle("Keep cleanup history", isOn: $settings.keepCleanupHistory)
                                .toggleStyle(.switch)
                                .onChange(of: settings.keepCleanupHistory) { _, enabled in
                                    auditLog.applyKeepHistorySetting(enabled)
                                }

                            Text("Saves what moved to Trash across launches. Turn off to keep history session-only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            NavigationLink(value: AppRoute.history) {
                                Text("View cleanup history")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(MSTheme.accent)
                            }
                            .buttonStyle(.msActionable)
                        }
                    }
                }
                .padding(MSTheme.pagePadding)
            }
        }
        .appDestinationChrome(
            title: "Settings",
            onBack: { AppNavigation.popLast($path) }
        )
        .onAppear {
            auditLog.applyKeepHistorySetting(settings.keepCleanupHistory)
        }
    }

    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        if path == home { return "~" }
        return path
    }
}

#Preview {
    NavigationStack {
        SettingsView(path: .constant(NavigationPath()))
            .environmentObject(AppSettings())
            .environmentObject(AuditLogService())
    }
}
