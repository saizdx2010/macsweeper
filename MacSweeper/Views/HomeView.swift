import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auditLog: AuditLogService

    @State private var snapshot: DiskSpaceService.Snapshot?
    @State private var path = NavigationPath()

    private let diskSpace = DiskSpaceService()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 28) {
                Spacer()

                if let snapshot {
                    VStack(spacing: 12) {
                        Text(ByteCountFormatter.string(fromByteCount: snapshot.freeBytes, countStyle: .file))
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                        Text("free")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        ProgressView(value: snapshot.usedFraction)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 280)

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
                    ScanResultsView()
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
        .frame(minWidth: 420, minHeight: 360)
    }

    private var lastCleanLabel: String {
        guard let last = auditLog.lastClean else {
            return "Last clean: —"
        }
        let size = ByteCountFormatter.string(fromByteCount: last.freedBytes, countStyle: .file)
        return "Last clean: freed \(size)"
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
