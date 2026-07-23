import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auditLog: AuditLogService

    @AppStorage("includeDevMode") private var includeDevMode = false
    @StateObject private var scanSession = ScanSession()
    @State private var snapshot: DiskSpaceService.Snapshot?
    @State private var path = NavigationPath()
    @State private var ringDrawn = false
    @State private var hasFullDiskAccess = true

    private let diskSpace = DiskSpaceService()
    private let diskPressureThreshold = 0.85
    private let contentMaxWidth: CGFloat = 580

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
                            path: $path
                        )
                    case .results:
                        ScanResultsView(
                            session: scanSession,
                            includeDevMode: includeDevMode,
                            path: $path
                        )
                    case .detail(let result):
                        CategoryDetailView(result: result, path: $path)
                    case .clean(let results):
                        CleanFlowView(results: results, navigationPath: $path)
                    }
                }
        }
        // Keep window toolbar available whenever we leave Home.
        .toolbar(path.isEmpty ? .hidden : .visible, for: .windowToolbar)
    }

    private var homeRoot: some View {
        ZStack {
            StageBackground()

            VStack(spacing: 0) {
                Text("MacSweeper")
                    .font(MSTheme.wordmarkFont)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        splitHero
                        stackedHero
                    }
                    .padding(.top, 24)

                    coverageBand
                        .padding(.top, 28)

                    footerZone
                        .padding(.top, 20)
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 8)
            }
            .padding(MSTheme.pagePadding)
        }
        .frame(minWidth: 640, minHeight: 480)
        .navigationBarBackButtonHidden(true)
        .task {
            refreshHomeState()
            withAnimation(.easeOut(duration: 0.8)) {
                ringDrawn = true
            }
        }
        .onChange(of: path.count) { _, count in
            if count == 0 {
                refreshHomeState()
            }
        }
        .onChange(of: auditLog.lastClean) { _, _ in
            snapshot = diskSpace.currentSnapshot()
        }
    }

    // MARK: - Hero layouts

    private var splitHero: some View {
        HStack(alignment: .center, spacing: 28) {
            diskRing
            infoColumn(alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var stackedHero: some View {
        VStack(spacing: 20) {
            diskRing
            infoColumn(alignment: .center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var diskRing: some View {
        DiskRingView(
            usedFraction: ringDrawn ? (snapshot?.usedFraction ?? 0) : 0,
            lineWidth: MSTheme.homeRingLineWidth,
            size: MSTheme.homeRingSize,
            progressColor: isDiskUnderPressure ? MSTheme.pressure : MSTheme.accent
        ) {
            if let snapshot {
                VStack(spacing: 4) {
                    Text(ByteCountFormatter.string(fromByteCount: snapshot.freeBytes, countStyle: .file))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("free")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(MSTheme.titleFont)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeOut(duration: 0.8), value: ringDrawn)
    }

    private func infoColumn(alignment: HorizontalAlignment) -> some View {
        let textAlignment: TextAlignment = alignment == .leading ? .leading : .center
        return VStack(alignment: alignment, spacing: 12) {
            if let snapshot {
                Text(diskContextLabel(for: snapshot))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .multilineTextAlignment(textAlignment)
            }

            Text(tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryCTANavigationLink(
                title: "Scan My Mac",
                value: AppRoute.scanning
            )
            .frame(maxWidth: 280)
            .padding(.top, 4)

            if !hasFullDiskAccess {
                VStack(alignment: alignment, spacing: 4) {
                    Button("Full Disk Access needed → Open Settings") {
                        FullDiskAccessService.openSystemSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MSTheme.accent)
                    .multilineTextAlignment(textAlignment)

                    Text("Required to empty Trash.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(textAlignment)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Coverage band

    private var coverageBand: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .opacity(0.45)

            Text("What a scan looks for")
                .font(.headline)
                .foregroundStyle(.primary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(coverageColumns) { column in
                        coverageColumnView(column)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(coverageColumns) { column in
                        coverageColumnView(column)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coverageColumns: [CoverageColumn] {
        [
            CoverageColumn(
                id: "safe",
                title: "Safe",
                blurb: "Regenerable caches, logs, Quick Look"
            ),
            CoverageColumn(
                id: "review",
                title: "Review",
                blurb: "Downloads, Mail, Xcode leftovers"
            ),
            CoverageColumn(
                id: "manual",
                title: "Manual",
                blurb: manualCoverageBlurb
            ),
        ]
    }

    private var manualCoverageBlurb: String {
        if includeDevMode {
            return "Homebrew cleanup · Docker prune"
        }
        return "Copy-and-run commands when needed"
    }

    private func coverageColumnView(_ column: CoverageColumn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(column.title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
            Text(column.blurb)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footerZone: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .opacity(0.5)

            Toggle("Include Dev mode", isOn: $includeDevMode)
                .toggleStyle(.switch)

            Text(devModeCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(lastCleanLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    // MARK: - Labels

    private var tagline: String {
        if isDiskUnderPressure {
            return "Disk getting tight — scan to see what you can reclaim"
        }
        return "Reclaim space safely — preview before anything moves"
    }

    private var devModeCaption: String {
        if includeDevMode {
            return "Also scans project folders for node_modules and virtualenvs."
        }
        return "Scans project folders for node_modules and virtualenvs."
    }

    private var lastCleanLabel: String {
        guard let last = auditLog.lastClean else {
            return "Last clean: —"
        }
        let size = ByteCountFormatter.string(fromByteCount: last.freedBytes, countStyle: .file)
        let when = Self.relativeFormatter.localizedString(for: last.date, relativeTo: Date())
        return "Last clean: \(size) · \(last.itemCount) items · \(when)"
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
}

private struct CoverageColumn: Identifiable {
    let id: String
    let title: String
    let blurb: String
}

enum AppRoute: Hashable {
    case scanning
    case results
    case detail(ScanResult)
    case clean([ScanResult])
}

#Preview {
    HomeView()
        .environmentObject(AuditLogService())
}
