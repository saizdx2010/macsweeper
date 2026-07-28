import SwiftUI

struct ScanResultsView: View {
    @ObservedObject var session: ScanSession
    let includeDevMode: Bool
    @Binding var path: NavigationPath

    @AppStorage("includeDevMode") private var includeDevModeStorage = false
    @AppStorage("didSeeResultsTip") private var didSeeResultsTip = false
    @State private var cardsVisible = false

    private var selectedBytes: Int64 { session.selectedBytes }
    private var totalBytes: Int64 { session.totalBytes }
    private var isDevModeEnabled: Bool { includeDevMode || includeDevModeStorage }

    private var cleanButtonTitle: String {
        let size = ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)
        return "Clean \(size)"
    }

    var body: some View {
        ZStack {
            StageBackground()

            VStack(spacing: 0) {
                content

                if hasListContent {
                    footerBar
                }
            }
        }
        .appDestinationChrome(
            title: "Results",
            subtitle: hasListContent
                ? "Selected \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))"
                : nil,
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
            withAnimation(.easeOut(duration: 0.35).delay(0.05)) {
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
            ScrollView {
                VStack(alignment: .leading, spacing: MSTheme.sectionSpacing) {
                    headerBand
                        .opacity(cardsVisible ? 1 : 0)

                    if !didSeeResultsTip {
                        tipBanner
                    }

                    if !session.coreIndices.isEmpty {
                        section(title: "Reclaimable", indices: session.coreIndices)
                    }

                    if !session.devIndices.isEmpty {
                        section(title: "Dev", indices: session.devIndices)
                    }

                    Text("Sizes are approximate (allocated disk use; hard links counted once).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(MSTheme.pagePadding)
            }
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

    private var tipBanner: some View {
        MSCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(MSTheme.accent)
                    .accessibilityHidden(true)

                Text("Safe items are checked; expand a row to review paths.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    didSeeResultsTip = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.msActionable)
                .accessibilityLabel("Dismiss tip")
            }
        }
    }

    private var headerBand: some View {
        MSCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(MSTheme.accent)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.2), value: selectedBytes)
                }
            }
        }
    }

    private func section(title: String, indices: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ForEach(Array(indices.enumerated()), id: \.element) { offset, index in
                CategoryCardRow(
                    result: $session.results[index],
                    showsSelection: true,
                    showsChevron: true,
                    onDetails: {
                        path.append(AppRoute.detail(categoryID: session.results[index].category.id))
                    }
                )
                .opacity(cardsVisible ? 1 : 0)
                .offset(y: cardsVisible ? 0 : 8)
                .animation(
                    .easeOut(duration: 0.3).delay(Double(offset) * 0.03),
                    value: cardsVisible
                )
            }
        }
    }

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack {
                Spacer(minLength: 8)

                PrimaryCTANavigationLink(
                    title: cleanButtonTitle,
                    value: AppRoute.clean(session.selectedResults),
                    isEnabled: !session.selectedResults.isEmpty
                )
                .frame(maxWidth: 240)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, MSTheme.pagePadding)
            .padding(.vertical, 14)
            .background(MSTheme.canvas.opacity(0.95))
        }
    }
}

#Preview {
    NavigationStack {
        ScanResultsView(
            session: ScanSession(),
            includeDevMode: false,
            path: .constant(NavigationPath())
        )
    }
}
