import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auditLog: AuditLogService
    @EnvironmentObject private var settings: AppSettings

    @AppStorage("includeDevMode") private var includeDevMode = false
    @StateObject private var scanSession = ScanSession()
    @State private var snapshot: DiskSpaceService.Snapshot?
    @State private var path = NavigationPath()
    @State private var ringDrawn = false
    @State private var hasFullDiskAccess = true
    @State private var showHelp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let diskSpace = DiskSpaceService()
    private let diskPressureThreshold = 0.85

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var isDiskUnderPressure: Bool {
        (snapshot?.usedFraction ?? 0) >= diskPressureThreshold
    }

    var body: some View {
        NavigationStack(path: $path) {
            homeRoot
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .scanning:
                        ScanningView(
                            session: scanSession,
                            includeDevMode: includeDevMode,
                            extraDevRoots: settings.customDevScanRoots,
                            path: $path
                        )
                    case .results:
                        ScanResultsView(
                            session: scanSession,
                            includeDevMode: includeDevMode,
                            path: $path
                        )
                    case .detail(let categoryID):
                        if let binding = scanSession.binding(forCategoryID: categoryID) {
                            CategoryDetailView(result: binding, path: $path)
                        } else {
                            ContentUnavailableView(
                                "Category unavailable",
                                systemImage: "questionmark.folder",
                                description: Text("Rescan to refresh results.")
                            )
                            .appDestinationChrome(
                                title: "Detail",
                                onBack: { AppNavigation.popLast($path) }
                            )
                        }
                    case .clean(let results):
                        CleanFlowView(results: results, navigationPath: $path)
                    case .settings:
                        SettingsView(path: $path)
                    case .history:
                        CleanupHistoryView(path: $path)
                    case .browse(let rootPath):
                        DiskBrowseView(
                            session: scanSession,
                            rootPath: rootPath,
                            path: $path
                        )
                    }
                }
        }
        .onChange(of: scanSession.phase) { _, phase in
            if phase == .finished { auditLog.finishScan(results: scanSession.results) }
        }
        .toolbar(.visible, for: .windowToolbar)
        .onAppear {
            auditLog.applyKeepHistorySetting(settings.keepCleanupHistory)
        }
    }

    private var homeRoot: some View {
        ZStack {
            StageBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                diskRing

                if let snapshot {
                    Text(diskContextLabel(for: snapshot))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.top, 14)
                }

                PrimaryCTANavigationLink(
                    title: "Scan Mac",
                    value: AppRoute.scanning,
                    icon: .scan,
                    expands: false
                )
                .frame(minWidth: MSTheme.ctaWidth)
                // Only while Home is on top; Results owns ⌘R (Rescan) once pushed.
                .keyboardShortcut(path.isEmpty ? KeyboardShortcut("r", modifiers: .command) : nil)
                .padding(.top, 26)

                Text(tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)

                if !hasFullDiskAccess {
                    Button("Full Disk Access is off. Open Settings") {
                        FullDiskAccessService.openSystemSettings()
                    }
                    .buttonStyle(.msActionable)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MSTheme.warning)
                    .help("Needed to empty the Trash")
                    .padding(.top, 10)
                }

                Spacer(minLength: 12)

                footer
            }
            .padding(.horizontal, MSTheme.pagePadding)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 640, minHeight: 520)
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HomeSectionBar(
                    onDisk: { path.append(AppRoute.browse(rootPath: nil)) },
                    onHistory: { path.append(AppRoute.history) },
                    onHelp: { showHelp = true }
                )
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    path.append(AppRoute.settings)
                } label: {
                    MSIconView(icon: .settings, size: 16)
                }
                .help("Settings")
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showHelp) {
            TroubleshootingView()
        }
        .task {
            refreshHomeState()
            withAnimation(ringAnimation) {
                ringDrawn = true
            }
        }
        .onChange(of: path.count) { _, count in
            if count == 0 {
                refreshHomeState()
                reanimateRing()
            }
        }
        .onChange(of: auditLog.lastClean) { _, _ in
            snapshot = diskSpace.currentSnapshot()
            reanimateRing()
        }
    }

    private var ringAnimation: Animation {
        MSMotion.resolve(.smooth(duration: 0.9), reduceMotion: reduceMotion)
    }

    private var diskRing: some View {
        DiskRingView(
            usedFraction: ringDrawn ? (snapshot?.usedFraction ?? 0) : 0,
            progressColors: isDiskUnderPressure ? MSTheme.pressureColors : MSTheme.brandColors
        ) {
            if let snapshot {
                VStack(spacing: 4) {
                    CountingBytesText(value: snapshot.freeBytes, isRevealed: ringDrawn)
                        .font(MSTheme.displayFont)
                    Text("free")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(MSTheme.titleFont)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(ringAnimation, value: ringDrawn)
        .accessibilityValue(diskRingAccessibilityValue)
    }

    private var diskRingAccessibilityValue: String {
        guard let snapshot else { return "Disk space unavailable" }
        let free = ByteCountFormatter.string(fromByteCount: snapshot.freeBytes, countStyle: .file)
        let pct = Int((snapshot.usedFraction * 100).rounded())
        return "\(free) free, \(pct) percent used"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Dev mode", isOn: $includeDevMode)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .help(devModeCaption)

            Spacer(minLength: 12)

            Text(footerStatus)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: 560)
    }

    // MARK: - Labels

    private var tagline: String {
        if isDiskUnderPressure {
            return "Your disk is nearly full. A scan shows what is safe to remove."
        }
        return "Nothing is removed until you review it."
    }

    private var devModeCaption: String {
        let customCount = settings.customDevRoots.count
        if customCount > 0 {
            return "Also scan project folders, plus \(customCount) custom Dev root\(customCount == 1 ? "" : "s"), for node_modules, virtualenvs and build caches."
        }
        return "Also scan project folders for node_modules, virtualenvs and build caches."
    }

    private var footerStatus: String {
        if settings.keepCleanupHistory, let total = auditLog.lifetime, !auditLog.entries.isEmpty {
            let freed = ByteCountFormatter.string(fromByteCount: total.freedBytes, countStyle: .file)
            return "\(freed) freed since \(total.firstDate.formatted(date: .abbreviated, time: .omitted))"
        }
        guard let last = auditLog.lastClean else {
            return "No cleans yet"
        }
        let size = ByteCountFormatter.string(fromByteCount: last.freedBytes, countStyle: .file)
        let when = Self.relativeFormatter.localizedString(for: last.date, relativeTo: Date())
        return "Last clean \(size) \(when)"
    }

    private func diskContextLabel(for snapshot: DiskSpaceService.Snapshot) -> String {
        let used = ByteCountFormatter.string(fromByteCount: snapshot.usedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: snapshot.totalBytes, countStyle: .file)
        let pct = Int((snapshot.usedFraction * 100).rounded())
        return "\(used) used of \(total) · \(pct)%"
    }

    private func refreshHomeState() {
        snapshot = diskSpace.currentSnapshot()
        hasFullDiskAccess = FullDiskAccessService.isGranted()
    }

    private func reanimateRing() {
        ringDrawn = false
        withAnimation(ringAnimation) {
            ringDrawn = true
        }
    }
}

/// Toolbar pill with the secondary destinations: Disk, History, Help.
private struct HomeSectionBar: View {
    let onDisk: () -> Void
    let onHistory: () -> Void
    let onHelp: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            item("Disk", icon: .disk, action: onDisk)
            item("History", icon: .history, action: onHistory)
            item("Help", icon: .help, action: onHelp)
        }
        .padding(2)
        .background(Color.primary.opacity(0.05), in: Capsule(style: .continuous))
    }

    private func item(_ title: String, icon: MSIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                MSIconView(icon: icon, size: 13)
                Text(title)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
        .buttonStyle(MSActionableButtonStyle(cornerRadius: 99))
    }
}

enum AppRoute: Hashable {
    case scanning
    case results
    case detail(categoryID: String)
    case clean([ScanResult])
    case settings
    case history
    case browse(rootPath: String?)
}

#Preview {
    HomeView()
        .environmentObject(AuditLogService())
        .environmentObject(AppSettings())
}
