import SwiftUI

/// ncdu-style one-level disk browser (home-only).
struct DiskBrowseView: View {
    @ObservedObject var session: ScanSession
    @Binding var path: NavigationPath

    @StateObject private var browse: DiskBrowseService
    @State private var categories: [ScanCategory] = []
    @State private var showScanNeededAlert = false
    @State private var pendingCleanLabel = ""

    init(session: ScanSession, rootPath: String?, path: Binding<NavigationPath>) {
        self.session = session
        self._path = path
        _browse = StateObject(wrappedValue: DiskBrowseService(rootPath: rootPath))
    }

    var body: some View {
        ZStack {
            StageBackground()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: MSTheme.sectionSpacing) {
                        headerCard

                        if let error = browse.errorMessage {
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.red)
                        }

                        entriesCard
                    }
                    .padding(MSTheme.pagePadding)
                    .padding(.bottom, 72)
                }

                footerBar
            }
        }
        .appDestinationChrome(
            title: "Browse disk",
            subtitle: browse.isMeasuring ? "Measuring…" : nil,
            onBack: { AppNavigation.popLast($path) }
        )
        .task {
            browse.loadDirectory(browse.currentPath)
            await loadCategories()
        }
        .onDisappear {
            browse.cancel()
        }
        .alert("Scan first", isPresented: $showScanNeededAlert) {
            Button("Scan My Mac") {
                path.append(AppRoute.scanning)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Run a scan to open “\(pendingCleanLabel)” in the clean flow. Browse never trashes folders on its own.")
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        MSCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if browse.canGoUp {
                        Button {
                            browse.goUp()
                        } label: {
                            Label("Up", systemImage: "chevron.up")
                                .font(.callout.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(MSTheme.accent)
                    }

                    Text(displayPath(browse.currentPath))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Text("Sizes are approximate (allocated disk use; hard links counted once in this folder).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if browse.isMeasuring {
                    ProgressView(value: progressFraction)
                        .tint(MSTheme.accent)
                }
            }
        }
    }

    private var entriesCard: some View {
        MSCard {
            if browse.entries.isEmpty && !browse.isMeasuring {
                Text("This folder is empty or unreadable.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(browse.entries.enumerated()), id: \.element.id) { index, entry in
                        entryRow(entry)
                        if index < browse.entries.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: DiskBrowseEntry) -> some View {
        let coverage = coverage(for: entry.path)
        let maxBytes = max(browse.totalKnownBytes, 1)
        let fraction: CGFloat = {
            guard let bytes = entry.byteCount else { return 0 }
            return CGFloat(Double(bytes) / Double(maxBytes))
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: entry.canDrillIn ? "folder.fill" : (entry.isPackage ? "app.fill" : "doc"))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if let match = coverage {
                        Button {
                            openCleanable(match)
                        } label: {
                            Text("Cleanable · \(match.label)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MSTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 8)

                Group {
                    if let bytes = entry.byteCount {
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if browse.isMeasuring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(minWidth: 64, alignment: .trailing)

                if entry.canDrillIn {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(MSTheme.accent.opacity(0.45))
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.canDrillIn {
                browse.drill(into: entry)
            }
        }
    }

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                SecondaryCTAButton(title: "Choose folder…", expands: false) {
                    if let chosen = browse.chooseFolderInteractively() {
                        browse.loadDirectory(chosen)
                    }
                }

                Spacer()

                if browse.isMeasuring {
                    SecondaryCTAButton(title: "Cancel", expands: false) {
                        browse.cancel()
                    }
                }
            }
            .padding(.horizontal, MSTheme.pagePadding)
            .padding(.vertical, 12)
            .background(MSTheme.canvas.opacity(0.92))
        }
    }

    // MARK: - Helpers

    private var progressFraction: Double {
        guard !browse.entries.isEmpty else { return 0 }
        return min(1, Double(browse.measuredCount) / Double(browse.entries.count))
    }

    private func coverage(for path: String) -> RuleCoverageMatch? {
        RuleCoverage.match(
            path: path,
            scanResults: session.results,
            categories: categories
        )
    }

    private func openCleanable(_ match: RuleCoverageMatch) {
        if session.binding(forCategoryID: match.categoryID) != nil {
            path.append(AppRoute.detail(categoryID: match.categoryID))
        } else {
            pendingCleanLabel = match.label
            showScanNeededAlert = true
        }
    }

    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func loadCategories() async {
        do {
            categories = try await ScanEngine().loadCategories()
        } catch {
            categories = []
        }
    }
}
