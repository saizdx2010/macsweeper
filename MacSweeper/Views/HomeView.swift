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
                Spacer(minLength: 12)

                VStack(spacing: 20) {
                    Text("MacSweeper")
                        .font(MSTheme.wordmarkFont)
                        .foregroundStyle(.primary)

                    DiskRingView(
                        usedFraction: ringDrawn ? (snapshot?.usedFraction ?? 0) : 0,
                        lineWidth: MSTheme.heroRingLineWidth,
                        size: MSTheme.heroRingSize,
                        progressColor: isDiskUnderPressure ? MSTheme.pressure : MSTheme.accent
                    ) {
                        if let snapshot {
                            VStack(spacing: 4) {
                                Text(ByteCountFormatter.string(fromByteCount: snapshot.freeBytes, countStyle: .file))
                                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text("free")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("—")
                                .font(MSTheme.displayFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .animation(.easeOut(duration: 0.8), value: ringDrawn)

                    if let snapshot {
                        Text(diskContextLabel(for: snapshot))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Text(tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)

                    Text("caches · logs · Xcode · Trash")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    PrimaryCTANavigationLink(
                        title: "Scan My Mac",
                        value: AppRoute.scanning
                    )
                    .frame(maxWidth: 320)
                }

                Spacer(minLength: 20)

                VStack(spacing: 10) {
                    Toggle("Include Dev mode", isOn: $includeDevMode)
                        .toggleStyle(.switch)
                        .frame(maxWidth: 320)

                    Text(devModeCaption)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)

                    Text(lastCleanLabel)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)

                    if !hasFullDiskAccess {
                        Button("Full Disk Access needed → Open Settings") {
                            FullDiskAccessService.openSystemSettings()
                        }
                        .buttonStyle(.plain)
                        .font(.footnote)
                        .foregroundStyle(MSTheme.accent)
                    }
                }
                .padding(.bottom, 8)
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

    private var tagline: String {
        if isDiskUnderPressure {
            return "Disk getting tight — scan to see what you can reclaim"
        }
        return "Reclaim space safely — preview before anything moves"
    }

    private var devModeCaption: String {
        if includeDevMode {
            return "Also scans: node_modules · venvs · Homebrew · Docker"
        }
        return "Scans project folders for node_modules and virtualenvs, plus Homebrew and Docker guidance."
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
