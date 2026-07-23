import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auditLog: AuditLogService

    @AppStorage("includeDevMode") private var includeDevMode = false
    @StateObject private var scanSession = ScanSession()
    @State private var snapshot: DiskSpaceService.Snapshot?
    @State private var path = NavigationPath()
    @State private var ringDrawn = false

    private let diskSpace = DiskSpaceService()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        NavigationStack(path: $path) {
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
                            progressColor: MSTheme.accent
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
                            Text("\(Int((snapshot.usedFraction * 100).rounded()))% used")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text("Reclaim space safely — preview before anything moves")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)

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

                        Text("Scans project folders for node_modules and virtualenvs, plus Homebrew and Docker guidance.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)

                        Text(lastCleanLabel)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.bottom, 8)
                }
                .padding(MSTheme.pagePadding)
            }
            .frame(minWidth: 640, minHeight: 480)
            .toolbar(.hidden, for: .windowToolbar)
            .navigationBarBackButtonHidden(true)
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
                    CategoryDetailView(result: result)
                case .clean(let results):
                    CleanFlowView(results: results, navigationPath: $path)
                }
            }
            .task {
                snapshot = diskSpace.currentSnapshot()
                withAnimation(.easeOut(duration: 0.8)) {
                    ringDrawn = true
                }
            }
            .onChange(of: auditLog.lastClean) { _, _ in
                snapshot = diskSpace.currentSnapshot()
            }
        }
    }

    private var lastCleanLabel: String {
        guard let last = auditLog.lastClean else {
            return "Last clean: —"
        }
        let size = ByteCountFormatter.string(fromByteCount: last.freedBytes, countStyle: .file)
        let when = Self.relativeFormatter.localizedString(for: last.date, relativeTo: Date())
        return "Last clean: freed \(size) · \(when)"
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
