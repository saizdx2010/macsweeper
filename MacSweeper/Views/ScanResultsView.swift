import SwiftUI

struct ScanResultsView: View {
    let includeDevMode: Bool

    @State private var results: [ScanResult] = []
    @State private var isScanning = false
    @State private var wasCancelled = false
    @State private var errorMessage: String?
    @State private var loadedRuleCount = 0
    @State private var scannedRuleCount = 0
    @State private var scanTask: Task<Void, Never>?

    private let engine = ScanEngine()

    private var coreIndices: [Int] {
        results.indices.filter { !results[$0].category.isDevGroup }
    }

    private var devIndices: [Int] {
        results.indices.filter { results[$0].category.isDevGroup }
    }

    private var selectedBytes: Int64 {
        results.filter(\.isSelected).reduce(0) { $0 + $1.totalBytes }
    }

    private var totalBytes: Int64 {
        results.reduce(0) { $0 + $1.totalBytes }
    }

    private var titleText: String {
        if isScanning {
            return "Scanning…"
        }
        if errorMessage != nil || (results.isEmpty && !wasCancelled) {
            return "Results"
        }
        if results.isEmpty {
            return "Results"
        }
        return "Found \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
    }

    var body: some View {
        VStack(spacing: 0) {
            if isScanning && results.isEmpty {
                VStack(spacing: 16) {
                    ProgressView(scanProgressLabel)
                    Button("Cancel") {
                        cancelScan()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Scan failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if results.isEmpty {
                ContentUnavailableView(
                    wasCancelled ? "Scan cancelled" : "No reclaimable space found",
                    systemImage: wasCancelled ? "stop.circle" : "tray",
                    description: Text(
                        wasCancelled
                            ? "No categories finished before cancel."
                            : "Checked \(loadedRuleCount) rules under your home folder. Nothing matched with measurable size."
                    )
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if isScanning {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(scanProgressLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel") {
                                cancelScan()
                            }
                            .font(.caption)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }

                    List {
                        if !coreIndices.isEmpty {
                            Section("Reclaimable") {
                                ForEach(coreIndices, id: \.self) { index in
                                    categoryRow($results[index])
                                }
                            }
                        }

                        if !devIndices.isEmpty {
                            Section("Dev") {
                                ForEach(devIndices, id: \.self) { index in
                                    categoryRow($results[index])
                                }
                            }
                        }
                    }

                    Text("Sizes are approximate (allocated disk use; hard links counted once).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                }
            }

            Divider()

            HStack {
                Text("Selected: \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))")
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink("Clean Now", value: AppRoute.clean(results.filter(\.isSelected)))
                    .disabled(isScanning || results.filter(\.isSelected).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(titleText)
        .toolbar {
            if !isScanning {
                ToolbarItem(placement: .primaryAction) {
                    Button("Rescan") {
                        startScan()
                    }
                }
            }
        }
        .onAppear {
            if results.isEmpty && !isScanning && errorMessage == nil && !wasCancelled {
                startScan()
            }
        }
        .onDisappear {
            cancelScan()
        }
    }

    @ViewBuilder
    private func categoryRow(_ result: Binding<ScanResult>) -> some View {
        NavigationLink(value: AppRoute.detail(result.wrappedValue)) {
            HStack {
                Toggle("", isOn: result.isSelected)
                    .labelsHidden()
                    .disabled(result.wrappedValue.category.risk == .manual)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.wrappedValue.category.label)
                    Text(result.wrappedValue.category.risk.displayName)
                        .font(.caption)
                        .foregroundStyle(riskColor(result.wrappedValue.category.risk))
                }

                Spacer()

                if result.wrappedValue.category.risk == .manual, result.wrappedValue.totalBytes == 0 {
                    Text("Guide")
                        .foregroundStyle(.secondary)
                } else {
                    Text(ByteCountFormatter.string(fromByteCount: result.wrappedValue.totalBytes, countStyle: .file))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var scanProgressLabel: String {
        if loadedRuleCount > 0 {
            return "Scanning rules… \(scannedRuleCount)/\(loadedRuleCount)"
        }
        return "Scanning…"
    }

    private func riskColor(_ risk: RiskLevel) -> Color {
        switch risk {
        case .safe:
            return .secondary
        case .moderate:
            return .orange
        case .risky:
            return .red.opacity(0.8)
        case .manual:
            return .secondary
        }
    }

    private func startScan() {
        cancelScan()
        results = []
        errorMessage = nil
        wasCancelled = false
        scannedRuleCount = 0
        loadedRuleCount = 0
        isScanning = true

        let includeDev = includeDevMode
        scanTask = Task {
            do {
                let categories = try await engine.loadCategories()
                let active = includeDev ? categories : categories.filter { !$0.isDevGroup }
                loadedRuleCount = active.count

                for try await event in engine.scanStream(includeDevMode: includeDev) {
                    try Task.checkCancellation()
                    switch event {
                    case .started(let ruleCount):
                        loadedRuleCount = ruleCount
                    case .ruleFinished(let current, let total):
                        scannedRuleCount = current
                        loadedRuleCount = total
                    case .category(let result):
                        insertSorted(result)
                    case .finished:
                        break
                    }
                }
            } catch is CancellationError {
                wasCancelled = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isScanning = false
            scanTask = nil
        }
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
    }

    private func insertSorted(_ result: ScanResult) {
        if let index = results.firstIndex(where: { $0.totalBytes < result.totalBytes }) {
            results.insert(result, at: index)
        } else {
            results.append(result)
        }
    }
}

#Preview {
    NavigationStack {
        ScanResultsView(includeDevMode: false)
    }
}
