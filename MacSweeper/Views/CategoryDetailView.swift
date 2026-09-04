import SwiftUI
#if os(macOS)
import AppKit
#endif

struct CategoryDetailView: View {
    @Binding var result: ScanResult
    @Binding var path: NavigationPath

    @State private var didCopyCommand = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var ageFilter: DetailAgeFilter = .any
    @State private var sizeFilter: DetailSizeFilter = .any
    @State private var searchText = ""
    @State private var displayLimit = DetailPathQuery.pageSize

    private var listsIndividualItems: Bool {
        result.category.scan == .listChildren
            || result.category.action == .emptyTrash
            || result.category.scan == .findNamedDirs
            || result.category.scan == .unusedApps
    }

    private var showsFilters: Bool {
        result.supportsItemSelection
            && (result.category.scan == .listChildren
                || result.category.scan == .findNamedDirs
                || result.category.scan == .unusedApps)
    }

    private var filteredPaths: [ScannedPath] {
        result.paths.filter { pathMatchesFilters($0) && DetailPathQuery.matchesSearch($0, query: searchText) }
    }

    private var displayedPaths: [ScannedPath] {
        DetailPathQuery.displayedPaths(filteredPaths, limit: displayLimit)
    }

    private var omittedPathCount: Int {
        DetailPathQuery.omittedCount(total: filteredPaths.count, limit: displayLimit)
    }

    private var itemsSectionTitle: String {
        listsIndividualItems ? "Items" : "Paths"
    }

    private var selectedSubtitle: String {
        let selected = result.selectedBytes
        let total = result.totalBytes
        let selectedLabel = ByteCountFormatter.string(fromByteCount: selected, countStyle: .file)
        if selected == total {
            return selectedLabel
        }
        let totalLabel = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return "\(selectedLabel) selected of \(totalLabel)"
    }

    var body: some View {
        ZStack {
            StageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: MSTheme.sectionSpacing) {
                    whyCard

                    if let command = result.category.guideCommand {
                        commandCard(command)
                    }

                    if showsFilters, result.supportsItemSelection {
                        filtersCard
                    }

                    if result.supportsItemSelection || !result.paths.isEmpty {
                        searchField
                    }

                    if result.supportsItemSelection {
                        selectionToolbar
                    }

                    pathsCard
                }
                .padding(MSTheme.pagePadding)
            }
        }
        .appDestinationChrome(
            title: result.category.label,
            subtitle: selectedSubtitle,
            onBack: { AppNavigation.popLast($path) }
        )
        .onChange(of: searchText) { _, _ in
            displayLimit = DetailPathQuery.pageSize
        }
        .onChange(of: ageFilter) { _, _ in
            displayLimit = DetailPathQuery.pageSize
        }
        .onChange(of: sizeFilter) { _, _ in
            displayLimit = DetailPathQuery.pageSize
        }
        .onDisappear {
            copyResetTask?.cancel()
        }
    }

    // MARK: - Cards

    private var whyCard: some View {
        MSCard {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MSTheme.accent.opacity(0.12))
                        .frame(width: 52, height: 52)
                    CategoryIcon(category: result.category, pointSize: 22)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        RiskBadge(risk: result.category.risk)
                        Text(result.category.risk.guidanceLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(result.category.description)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func commandCard(_ command: String) -> some View {
        MSCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Command")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Button(didCopyCommand ? "Copied" : "Copy command") {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    #endif
                    didCopyCommand = true
                    copyResetTask?.cancel()
                    copyResetTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        didCopyCommand = false
                    }
                }
                .disabled(didCopyCommand)

                Text("MacSweeper does not run this command. Paste it into Terminal yourself.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search paths", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.msActionable)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MSTheme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MSTheme.cardStroke, lineWidth: 1)
        )
    }

    private var filtersCard: some View {
        MSCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("FILTERS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                filterChipRow(
                    icon: "clock",
                    title: "Age",
                    selection: $ageFilter,
                    options: DetailAgeFilter.allCases
                ) { $0.label }

                filterChipRow(
                    icon: "externaldrive",
                    title: "Size",
                    selection: $sizeFilter,
                    options: DetailSizeFilter.allCases
                ) { $0.label }

                Text("Filters change what’s shown. Use Select visible to check matching items.")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.85))
            }
        }
    }

    private func filterChipRow<T: Hashable & Identifiable>(
        icon: String,
        title: String,
        selection: Binding<T>,
        options: [T],
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.hierarchical)

            HStack(spacing: 8) {
                ForEach(options) { option in
                    FilterChip(
                        title: label(option),
                        isSelected: selection.wrappedValue == option
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selection.wrappedValue = option
                        }
                    }
                }
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            Button("Select visible") {
                setVisibleSelection(true)
            }
            Button("Deselect visible") {
                setVisibleSelection(false)
            }
            Spacer()
            Text("\(result.selectedPathCount) of \(result.paths.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var pathsCard: some View {
        MSCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(itemsSectionTitle.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if result.paths.isEmpty {
                    Text(
                        result.category.guideCommand != nil
                            ? "No path sizes to list — use the command above."
                            : "No paths found for this category."
                    )
                    .foregroundStyle(.secondary)
                } else if filteredPaths.isEmpty {
                    Text("No items match the current filters.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(displayedPaths) { item in
                            pathRow(for: item)
                            if item.id != displayedPaths.last?.id {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    if omittedPathCount > 0 {
                        Button("Show more (\(omittedPathCount) remaining)") {
                            displayLimit += DetailPathQuery.pageSize
                        }
                        .buttonStyle(.msActionable)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(MSTheme.accent)
                    }
                    if listsIndividualItems {
                        Text("\(min(displayLimit, filteredPaths.count)) of \(filteredPaths.count) shown · sizes include folder contents")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func pathRow(for item: ScannedPath) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if result.supportsItemSelection {
                Button {
                    togglePath(item.id)
                } label: {
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.isSelected ? MSTheme.accent : Color.secondary.opacity(0.55))
                }
                .buttonStyle(.msActionable)
                .accessibilityLabel(item.isSelected ? "Selected" : "Not selected")
            }

            if listsIndividualItems {
                Image(systemName: itemIconName(for: item.path))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .lineLimit(2)
                        .help(item.displayPath)
                        .textSelection(.enabled)
                    if let date = item.contentModificationDate {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text(item.displayPath)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                FinderReveal.reveal(path: item.path)
            } label: {
                Image(systemName: "arrow.forward.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.msActionable)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal in Finder")
        }
        .padding(.vertical, 6)
        .opacity(item.isSelected || !result.supportsItemSelection ? 1 : 0.55)
        .contextMenu {
            Button("Reveal in Finder") {
                FinderReveal.reveal(path: item.path)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pathAccessibilityLabel(for: item))
    }

    private func pathAccessibilityLabel(for item: ScannedPath) -> String {
        let size = ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
        let name = listsIndividualItems ? item.displayName : item.displayPath
        let selection: String
        if result.supportsItemSelection {
            selection = item.isSelected ? "Selected. " : "Not selected. "
        } else {
            selection = ""
        }
        return "\(selection)\(name), \(size)"
    }

    // MARK: - Actions

    private func togglePath(_ id: String) {
        guard let index = result.paths.firstIndex(where: { $0.id == id }) else { return }
        result.paths[index].isSelected.toggle()
        result.syncCategorySelectionFromPaths()
    }

    private func setVisibleSelection(_ selected: Bool) {
        let visibleIDs = Set(filteredPaths.map(\.id))
        for index in result.paths.indices where visibleIDs.contains(result.paths[index].id) {
            result.paths[index].isSelected = selected
        }
        result.syncCategorySelectionFromPaths()
    }

    private func pathMatchesFilters(_ item: ScannedPath) -> Bool {
        DetailPathQuery.matchesFilters(item, age: ageFilter, size: sizeFilter)
    }

    private func itemIconName(for path: String) -> String {
        if path.hasSuffix(".app") { return "app" }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return "folder"
        }
        return "doc"
    }
}

// MARK: - Filters

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? MSTheme.accent : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(chipBackground, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(chipStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            #if os(macOS)
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
            #endif
        }
        .onDisappear {
            #if os(macOS)
            if isHovered { NSCursor.pop() }
            #endif
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var chipBackground: Color {
        if isSelected {
            return MSTheme.accent.opacity(0.16)
        }
        return Color.primary.opacity(isHovered ? 0.10 : 0.06)
    }

    private var chipStroke: Color {
        if isSelected {
            return MSTheme.accent.opacity(0.35)
        }
        return Color.primary.opacity(isHovered ? 0.12 : 0.06)
    }
}

#Preview {
    NavigationStack {
        CategoryDetailView(
            result: .constant(
                ScanResult(
                    category: ScanCategory(
                        id: "old_downloads",
                        label: "Downloads folder",
                        paths: ["~/Downloads"],
                        risk: .moderate,
                        description: "Everything currently in Downloads. Review carefully — may include keepers.",
                        scan: .listChildren,
                        icon: "arrow.down.circle"
                    ),
                    paths: [
                        ScannedPath(
                            path: NSHomeDirectory() + "/Downloads/Installer.dmg",
                            byteCount: 820_000_000,
                            isSelected: false,
                            contentModificationDate: Date().addingTimeInterval(-40 * 24 * 60 * 60)
                        )
                    ],
                    isSelected: false
                )
            ),
            path: .constant(NavigationPath())
        )
    }
}
