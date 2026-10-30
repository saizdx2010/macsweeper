import SwiftUI

struct ScanResultsView: View {
    @EnvironmentObject private var auditLog: AuditLogService
    @ObservedObject var session: ScanSession
    let includeDevMode: Bool
    @Binding var path: NavigationPath

    @AppStorage("includeDevMode") private var includeDevModeStorage = false
    @State private var cardsVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedBytes: Int64 { session.selectedBytes }
    private var totalBytes: Int64 { session.totalBytes }
    private var isDevModeEnabled: Bool { includeDevMode || includeDevModeStorage }

    private var cleanButtonTitle: String {
        guard selectedBytes > 0 else { return "Clean" }
        return "Clean \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))"
    }

    private var selectedLabel: String {
        guard selectedBytes > 0 else { return "Nothing selected yet" }
        return "\(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)) selected"
    }

    var body: some View {
        ZStack {
            StageBackground()
            content
        }
        .appDestinationChrome(
            title: "Results",
            onBack: { AppNavigation.popToRoot($path) }
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Rescan") {
                    path = NavigationPath()
                    path.append(AppRoute.scanning)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            if hasListContent {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Selection") {
                        Button("Select Safe") {
                            session.selectWhere(risk: .safe)
                        }
                        Button("Deselect Risky") {
                            session.deselectWhere(risk: .risky)
                        }
                        Divider()
                        Button("Deselect All") {
                            session.deselectAll()
                        }
                    }
                }
            }
        }
        .onAppear {
            withAnimation(MSMotion.resolve(MSMotion.base, reduceMotion: reduceMotion).delay(0.05)) {
                cardsVisible = true
            }
        }
    }

    private var hasListContent: Bool {
        !session.results.isEmpty
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .failed(let message):
            ContentUnavailableView(
                "Scan failed",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .cancelled where session.results.isEmpty:
            emptyState(
                title: "Scan cancelled",
                systemImage: "stop.circle",
                description: "No categories finished before cancel."
            )
        case _ where session.results.isEmpty:
            emptyState(
                title: "No reclaimable space found",
                systemImage: "tray",
                description: "Checked \(session.loadedRuleCount) rules under your home folder. Nothing matched with measurable size."
            )
        default:
            resultsPanel
        }
    }

    private func emptyState(title: String, systemImage: String, description: String) -> some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )

            VStack(spacing: 12) {
                SecondaryCTAButton(title: "Browse disk", expands: false) {
                    path.append(AppRoute.browse(rootPath: nil))
                }

                if !isDevModeEnabled {
                    SecondaryCTAButton(title: "Include Dev mode", expands: false) {
                        includeDevModeStorage = true
                        path = NavigationPath()
                        path.append(AppRoute.scanning)
                    }
                }

                PrimaryCTAButton(title: "Rescan", expands: false) {
                    path = NavigationPath()
                    path.append(AppRoute.scanning)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MSTheme.pagePadding)
    }

    // MARK: - Results sheet

    private var resultsPanel: some View {
        VStack(spacing: 0) {
            panelHeader
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Rectangle().fill(MSTheme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groups) { group in
                        groupSection(group)
                    }

                    Text("Sizes are approximate: allocated disk use, hard links counted once.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(22)
            }
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous)
                .fill(MSTheme.cardFill)
                .shadow(color: .black.opacity(0.10), radius: 18, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .offset(y: cardsVisible || reduceMotion ? 0 : 40)
        .opacity(cardsVisible ? 1 : 0)
    }

    private var panelHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountingBytesText(value: totalBytes, isRevealed: cardsVisible)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .animation(MSMotion.resolve(MSMotion.slow, reduceMotion: reduceMotion), value: cardsVisible)
                    Text("found")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text(selectedLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(MSMotion.fast, value: selectedBytes)
            }

            Spacer(minLength: 12)

            PrimaryCTANavigationLink(
                title: cleanButtonTitle,
                value: AppRoute.clean(session.selectedResults),
                icon: .clean,
                isEnabled: !session.selectedResults.isEmpty,
                expands: false
            )
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func groupSection(_ group: ResultGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MSSectionHeader(title: group.title, trailing: groupSizeLabel(group))
            .padding(.horizontal, 4)

            MSGroupedRows(items: group.indices.map(IndexedRow.init)) { offset, row in
                CategoryListRow(
                    result: $session.results[row.index],
                    change: auditLog.scanChanges[session.results[row.index].category.id],
                    onDetails: {
                        path.append(AppRoute.detail(categoryID: session.results[row.index].category.id))
                    }
                )
                .opacity(cardsVisible ? 1 : 0)
                .offset(y: cardsVisible || reduceMotion ? 0 : 8)
                .animation(rowAnimation(group.startOffset + offset), value: cardsVisible)
            }
        }
    }

    /// Group total, omitted for guide-only groups that measure nothing.
    private func groupSizeLabel(_ group: ResultGroup) -> String? {
        let bytes = group.indices.reduce(Int64(0)) { $0 + session.results[$1].totalBytes }
        return bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : nil
    }

    /// Stagger only the first few rows overall; the rest appear together.
    private func rowAnimation(_ position: Int) -> Animation {
        let delay = Double(min(position, MSMotion.staggerLimit)) * MSMotion.stagger
        return MSMotion.resolve(MSMotion.base, reduceMotion: reduceMotion).delay(delay + 0.1)
    }

    /// Results grouped by how much care they need, in display order.
    private var groups: [ResultGroup] {
        let indices = Array(session.results.indices)
        let buckets: [(String, String, (RiskLevel) -> Bool)] = [
            ("safe", "Safe to clean", { $0 == .safe }),
            ("review", "Review first", { $0 == .moderate || $0 == .risky }),
            ("manual", "Do it yourself", { $0 == .manual }),
        ]
        var offset = 0
        return buckets.compactMap { id, title, matches in
            let members = indices.filter { matches(session.results[$0].category.risk) }
            guard !members.isEmpty else { return nil }
            defer { offset += members.count }
            return ResultGroup(id: id, title: title, indices: members, startOffset: offset)
        }
    }
}

private struct ResultGroup: Identifiable {
    let id: String
    let title: String
    let indices: [Int]
    /// Position of the first row across all groups, for the stagger.
    let startOffset: Int
}

private struct IndexedRow: Identifiable {
    let index: Int
    var id: Int { index }
}

#Preview {
    NavigationStack {
        ScanResultsView(
            session: ScanSession(),
            includeDevMode: false,
            path: .constant(NavigationPath())
        ).environmentObject(AuditLogService())
    }
}
