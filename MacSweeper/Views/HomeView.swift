import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auditLog: AuditLogService

    @AppStorage("includeDevMode") private var includeDevMode = false
    @State private var snapshot: DiskSpaceService.Snapshot?
    @State private var path = NavigationPath()

    private let diskSpace = DiskSpaceService()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 28) {
                Spacer()

                if let snapshot {
                    VStack(spacing: 12) {
                        DiskRingView(usedFraction: snapshot.usedFraction) {
                            VStack(spacing: 4) {
                                Text(ByteCountFormatter.string(fromByteCount: snapshot.freeBytes, countStyle: .file))
                                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text("free")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("\(Int((snapshot.usedFraction * 100).rounded()))% used")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Unable to read disk space")
                        .foregroundStyle(.secondary)
                }

                Button("Scan My Mac") {
                    path.append(AppRoute.results)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(spacing: 6) {
                    Toggle("Include Dev mode", isOn: $includeDevMode)
                        .toggleStyle(.switch)
                        .frame(maxWidth: 280)

                    Text("Scans project folders for node_modules and virtualenvs, plus Homebrew and Docker guidance.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }

                Text(lastCleanLabel)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .navigationTitle("MacSweeper")
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .results:
                    ScanResultsView(includeDevMode: includeDevMode)
                case .detail(let result):
                    CategoryDetailView(result: result)
                case .clean(let results):
                    CleanFlowView(results: results, navigationPath: $path)
                }
            }
            .task {
                snapshot = diskSpace.currentSnapshot()
            }
            .onChange(of: auditLog.lastClean) { _, _ in
                snapshot = diskSpace.currentSnapshot()
            }
        }
        .frame(minWidth: 420, minHeight: 500)
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
    case results
    case detail(ScanResult)
    case clean([ScanResult])
}

#Preview {
    HomeView()
        .environmentObject(AuditLogService())
}
