import Foundation
import SwiftUI

/// Owns a single scan run shared by the theater and results screens.
@MainActor
final class ScanSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case finished
        case cancelled
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var results: [ScanResult] = []
    @Published private(set) var loadedRuleCount = 0
    @Published private(set) var scannedRuleCount = 0
    @Published private(set) var statusMessage = "Preparing…"

    private let engine = ScanEngine()
    private var scanTask: Task<Void, Never>?

    var progressFraction: Double {
        guard loadedRuleCount > 0 else { return 0 }
        return min(1, Double(scannedRuleCount) / Double(loadedRuleCount))
    }

    var totalBytes: Int64 {
        results.reduce(0) { $0 + $1.totalBytes }
    }

    var selectedBytes: Int64 {
        results.reduce(0) { $0 + $1.selectedBytes }
    }

    var selectedResults: [ScanResult] {
        results.compactMap { $0.selectingOnlyCheckedPaths() }
    }

    func index(forCategoryID id: String) -> Int? {
        results.firstIndex { $0.category.id == id }
    }

    func binding(forCategoryID id: String) -> Binding<ScanResult>? {
        guard let index = index(forCategoryID: id) else { return nil }
        return Binding(
            get: { self.results[index] },
            set: { self.results[index] = $0 }
        )
    }

    var coreIndices: [Int] {
        results.indices.filter { !results[$0].category.isDevGroup }
    }

    var devIndices: [Int] {
        results.indices.filter { results[$0].category.isDevGroup }
    }

    func selectWhere(risk: RiskLevel) {
        for index in results.indices where results[index].category.risk == risk {
            results[index].setAllPathsSelected(true)
        }
    }

    func deselectWhere(risk: RiskLevel) {
        for index in results.indices where results[index].category.risk == risk {
            results[index].setAllPathsSelected(false)
        }
    }

    func deselectAll() {
        for index in results.indices {
            results[index].setAllPathsSelected(false)
        }
    }

    func start(includeDevMode: Bool, extraDevRoots: [String] = []) {
        cancel()
        results = []
        loadedRuleCount = 0
        scannedRuleCount = 0
        statusMessage = "Preparing…"
        phase = .scanning

        let roots = extraDevRoots
        scanTask = Task {
            do {
                let categories = try await engine.loadCategories()
                let active = includeDevMode ? categories : categories.filter { !$0.isDevGroup }
                loadedRuleCount = active.count
                statusMessage = "Scanning rules…"

                for try await event in engine.scanStream(
                    includeDevMode: includeDevMode,
                    extraDevRoots: roots
                ) {
                    try Task.checkCancellation()
                    switch event {
                    case .started(let ruleCount):
                        loadedRuleCount = ruleCount
                        statusMessage = "Scanning…"
                    case .ruleFinished(let current, let total):
                        scannedRuleCount = current
                        loadedRuleCount = total
                        statusMessage = "Scanning rules… \(current)/\(total)"
                    case .category(let result):
                        insertSorted(result)
                        statusMessage = "Found \(result.category.label)"
                    case .finished:
                        statusMessage = "Scan complete"
                    }
                }
                phase = .finished
            } catch is CancellationError {
                phase = .cancelled
                statusMessage = "Scan cancelled"
            } catch {
                phase = .failed(error.localizedDescription)
                statusMessage = "Scan failed"
            }
            scanTask = nil
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning {
            phase = .cancelled
            statusMessage = "Scan cancelled"
        }
    }

    func rescan(includeDevMode: Bool, extraDevRoots: [String] = []) {
        start(includeDevMode: includeDevMode, extraDevRoots: extraDevRoots)
    }

    private func insertSorted(_ result: ScanResult) {
        if let index = results.firstIndex(where: { $0.totalBytes < result.totalBytes }) {
            results.insert(result, at: index)
        } else {
            results.append(result)
        }
    }
}
