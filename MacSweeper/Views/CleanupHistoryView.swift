import AppKit
import SwiftUI

struct CleanupHistoryView: View {
    @EnvironmentObject private var auditLog: AuditLogService
    @Binding var path: NavigationPath

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        ZStack {
            StageBackground()

            Group {
                if auditLog.entries.isEmpty {
                    ContentUnavailableView(
                        "No cleanup history yet",
                        systemImage: "clock",
                        description: Text("After you clean, moved items appear here with sizes and restore hints.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: MSTheme.sectionSpacing) {
                            MSCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recent cleanups")
                                        .font(.headline)
                                    Text("Items were moved to Trash. Restore from Trash in Finder, or use Undo right after a clean.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(auditLog.entries) { entry in
                                    historyRow(entry)
                                }
                            }

                            Button("Clear history") {
                                auditLog.clearSession()
                            }
                            .foregroundStyle(.secondary)
                        }
                        .padding(MSTheme.pagePadding)
                    }
                }
            }
        }
        .appDestinationChrome(
            title: "History",
            subtitle: auditLog.entries.isEmpty ? nil : "\(auditLog.entries.count) items",
            onBack: { AppNavigation.popLast($path) }
        )
        .toolbar {
            if !auditLog.entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Open Trash") {
                        openTrash()
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: AuditLogService.Entry) -> some View {
        MSCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.categoryID.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: entry.byteCount, countStyle: .file))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Text(displayPath(entry.path))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                Text(Self.relativeFormatter.localizedString(for: entry.timestamp, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func openTrash() {
        let trash = URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash", isDirectory: true)
        NSWorkspace.shared.open(trash)
    }
}

#Preview {
    NavigationStack {
        CleanupHistoryView(path: .constant(NavigationPath()))
            .environmentObject(AuditLogService())
    }
}
