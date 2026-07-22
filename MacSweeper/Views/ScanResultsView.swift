import SwiftUI

struct ScanResultsView: View {
    @State private var results: [ScanResult] = []
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var loadedRuleCount = 0

    private let engine = ScanEngine()

    private var selectedBytes: Int64 {
        results.filter(\.isSelected).reduce(0) { $0 + $1.totalBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isScanning {
                ProgressView("Scanning…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Scan failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if results.isEmpty {
                ContentUnavailableView(
                    "No reclaimable space found",
                    systemImage: "tray",
                    description: Text("Loaded \(loadedRuleCount) rules. Phase 1 will measure real sizes.")
                )
            } else {
                List {
                    ForEach($results) { $result in
                        NavigationLink(value: AppRoute.detail(result)) {
                            HStack {
                                Toggle("", isOn: $result.isSelected)
                                    .labelsHidden()
                                    .disabled(result.category.risk == .manual)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.category.label)
                                    Text(result.category.risk.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("Selected: \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))")
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink("Clean Now", value: AppRoute.clean(results.filter(\.isSelected)))
                    .disabled(results.filter(\.isSelected).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("Results")
        .task {
            await runScan()
        }
    }

    private func runScan() async {
        isScanning = true
        errorMessage = nil
        defer { isScanning = false }

        do {
            let categories = try await engine.loadCategories()
            loadedRuleCount = categories.count
            results = try await engine.scan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ScanResultsView()
    }
}
