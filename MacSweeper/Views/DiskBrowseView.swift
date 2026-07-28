import SwiftUI

/// ncdu-style one-level disk browser (home-only).
struct DiskBrowseView: View {
    @ObservedObject var session: ScanSession
    @Binding var path: NavigationPath

    @StateObject private var browse: DiskBrowseService
    @State private var categories: [ScanCategory] = []
    @State private var showScanNeededAlert = false
    @State private var pendingCleanLabel = ""
    @State private var sortMode: BrowseSortMode = .size
    @State private var focusedIndex: Int = 0
    @FocusState private var listFocused: Bool

    init(session: ScanSession, rootPath: String?, path: Binding<NavigationPath>) {
        self.session = session
        self._path = path
        _browse = StateObject(wrappedValue: DiskBrowseService(rootPath: rootPath))
    }

    private var sortedEntries: [DiskBrowseEntry] {
        switch sortMode {
        case .name:
            return browse.entries.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .size:
            return browse.entries.sorted { lhs, rhs in
                let lb = lhs.byteCount ?? -1
                let rb = rhs.byteCount ?? -1
                if lb != rb { return lb > rb }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
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
            listFocused = true
        }
        .onDisappear {
            browse.cancel()
        }
        .onChange(of: sortedEntries.map(\.id)) { _, _ in
            if focusedIndex >= sortedEntries.count {
                focusedIndex = max(0, sortedEntries.count - 1)
            }
        }
        .alert("Scan first", isPresented: $showScanNeededAlert) {
            Button("Scan My Mac") {
                path.append(AppRoute.scanning)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Run a scan to open “\(pendingCleanLabel)” in the clean flow. Browse never trashes folders on its own.")
        }
        .focusable()
        .focused($listFocused)
        .onKeyPress(.upArrow) {
            moveFocus(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveFocus(1)
            return .handled
        }
        .onKeyPress(.return) {
            activateFocused()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if browse.canGoUp {
                browse.goUp()
                focusedIndex = 0
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.delete) {
            if browse.canGoUp {
                browse.goUp()
                focusedIndex = 0
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        MSCard {
            VStack(alignment: .leading, spacing: 10) {
                breadcrumbRow

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

    private var breadcrumbRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(browse.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }

                    Button {
                        browse.loadDirectory(crumb.path)
                        focusedIndex = 0
                    } label: {
                        Text(crumb.title)
                            .font(.system(.body, design: .monospaced).weight(index == browse.breadcrumbs.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == browse.breadcrumbs.count - 1 ? .primary : MSTheme.accent)
                    }
                    .buttonStyle(.msActionable)
                    .disabled(index == browse.breadcrumbs.count - 1)
                    .accessibilityLabel(crumb.title == "~" ? "Home folder" : crumb.title)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Path breadcrumbs")
    }

    private var entriesCard: some View {
        MSCard {
            if browse.entries.isEmpty && !browse.isMeasuring {
                Text("This folder is empty or unreadable.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    sortHeader
                        .padding(.bottom, 8)

                    Divider().opacity(0.35)

                    ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
                        entryRow(entry, index: index)
                        if index < sortedEntries.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }

    private var sortHeader: some View {
        HStack(spacing: 10) {
            Text("Sort")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Picker("Sort", selection: $sortMode) {
                ForEach(BrowseSortMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 180)
            .accessibilityLabel("Sort by")
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private func entryRow(_ entry: DiskBrowseEntry, index: Int) -> some View {
        let coverage = coverage(for: entry.path)
        let maxBytes = max(browse.totalKnownBytes, 1)
        let fraction: CGFloat = {
            guard let bytes = entry.byteCount else { return 0 }
            return CGFloat(Double(bytes) / Double(maxBytes))
        }()
        let isFocused = index == focusedIndex && !sortedEntries.isEmpty

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: entry.canDrillIn ? "folder.fill" : (entry.isPackage ? "app.fill" : "doc"))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)

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
                        .buttonStyle(.msActionable)
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
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MSTheme.accent.opacity(isFocused ? 0.10 : 0))
        )
        .actionableHover(isEnabled: entry.canDrillIn, cornerRadius: 8)
        .onTapGesture {
            focusedIndex = index
            if entry.canDrillIn {
                browse.drill(into: entry)
                focusedIndex = 0
            }
        }
        .contextMenu {
            Button("Reveal in Finder") {
                FinderReveal.reveal(path: entry.path)
            }
            if entry.canDrillIn {
                Button("Open") {
                    browse.drill(into: entry)
                    focusedIndex = 0
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entryAccessibilityLabel(entry))
        .accessibilityAddTraits(entry.canDrillIn ? .isButton : [])
    }

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                SecondaryCTAButton(title: "Choose folder…", expands: false) {
                    if let chosen = browse.chooseFolderInteractively() {
                        browse.loadDirectory(chosen)
                        focusedIndex = 0
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

    private func moveFocus(_ delta: Int) {
        guard !sortedEntries.isEmpty else { return }
        let next = focusedIndex + delta
        focusedIndex = min(max(0, next), sortedEntries.count - 1)
    }

    private func activateFocused() {
        guard sortedEntries.indices.contains(focusedIndex) else { return }
        let entry = sortedEntries[focusedIndex]
        if entry.canDrillIn {
            browse.drill(into: entry)
            focusedIndex = 0
        } else {
            FinderReveal.reveal(path: entry.path)
        }
    }

    private func entryAccessibilityLabel(_ entry: DiskBrowseEntry) -> String {
        let size: String
        if let bytes = entry.byteCount {
            size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        } else {
            size = "size unknown"
        }
        let kind = entry.canDrillIn ? "folder" : "item"
        return "\(entry.name), \(kind), \(size)"
    }

    private func loadCategories() async {
        do {
            categories = try await ScanEngine().loadCategories()
        } catch {
            categories = []
        }
    }
}

private enum BrowseSortMode: String, CaseIterable, Identifiable {
    case name
    case size

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Name"
        case .size: return "Size"
        }
    }
}
