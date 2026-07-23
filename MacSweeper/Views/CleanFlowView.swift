import AppKit
import SwiftUI

struct CleanFlowView: View {
    let results: [ScanResult]
    @Binding var navigationPath: NavigationPath

    @EnvironmentObject private var auditLog: AuditLogService

    @State private var phase: Phase = .confirm
    @State private var outcome: CleanupService.Outcome?
    @State private var showConfirmation = false
    @State private var errorMessage: String?
    @State private var isRestoring = false
    @State private var didUndo = false

    private let cleanup = CleanupService()

    private var totalBytes: Int64 {
        results.reduce(0) { $0 + $1.totalBytes }
    }

    private var totalItems: Int {
        results.reduce(0) { $0 + $1.paths.count }
    }

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    enum Phase {
        case confirm
        case working
        case done
    }

    var body: some View {
        Group {
            switch phase {
            case .confirm:
                confirmView
            case .working:
                ProgressView(isRestoring ? "Restoring…" : "Moving to Trash…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done:
                doneView
            }
        }
        .navigationTitle("Clean")
        .padding()
        .confirmationDialog(
            "Move \(sizeLabel) to Trash?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await performClean() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alert("Clean failed", isPresented: Binding(
            get: { errorMessage != nil && phase == .confirm },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var confirmationMessage: String {
        let categoryWord = results.count == 1 ? "category" : "categories"
        let itemWord = totalItems == 1 ? "item" : "items"
        return "\(results.count) \(categoryWord) · \(totalItems) \(itemWord). Items move to Trash and can be restored anytime."
    }

    private var confirmView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to clean \(sizeLabel)")
                .font(.title2.weight(.semibold))

            List(results) { result in
                HStack {
                    Text(result.category.label)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 120)

            Text("Items move to Trash. You can restore them from Trash anytime.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    navigationPath.removeLast()
                }
                Spacer()
                Button("Move to Trash") {
                    showConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(results.isEmpty)
            }
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()

            if didUndo {
                Text("Restored \(outcome?.itemCount ?? 0) items")
                    .font(.title.weight(.semibold))
                Text("Files were moved back from Trash.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Freed \(ByteCountFormatter.string(fromByteCount: outcome?.freedBytes ?? 0, countStyle: .file))")
                    .font(.title.weight(.semibold))
                Text("\(outcome?.itemCount ?? 0) items moved to Trash")
                    .foregroundStyle(.secondary)

                if let failures = outcome?.failures, !failures.isEmpty {
                    Text("\(failures.count) item\(failures.count == 1 ? "" : "s") could not be moved.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Text("Undo restores items still in Trash, or open Trash in Finder.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                if !didUndo {
                    Button("Open Trash") {
                        openTrash()
                    }

                    if let moved = outcome?.moved, !moved.isEmpty {
                        Button("Undo") {
                            Task { await performUndo() }
                        }
                    }
                }

                Button("Done") {
                    dismissToHome()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func performClean() async {
        phase = .working
        errorMessage = nil
        didUndo = false
        do {
            let result = try await cleanup.moveToTrash(results)
            outcome = result
            if !result.moved.isEmpty {
                auditLog.finishClean(moved: result.moved)
            }
            phase = .done
        } catch is CancellationError {
            phase = .confirm
        } catch {
            errorMessage = error.localizedDescription
            phase = .confirm
        }
    }

    private func performUndo() async {
        guard let moved = outcome?.moved, !moved.isEmpty else { return }
        isRestoring = true
        phase = .working
        defer { isRestoring = false }

        do {
            let restored = try await cleanup.restoreFromTrash(moved)
            outcome = restored
            didUndo = restored.itemCount > 0
            phase = .done
        } catch {
            errorMessage = error.localizedDescription
            phase = .done
        }
    }

    private func openTrash() {
        let trash = URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash", isDirectory: true)
        NSWorkspace.shared.open(trash)
    }

    private func dismissToHome() {
        navigationPath = NavigationPath()
    }
}

#Preview {
    NavigationStack {
        CleanFlowView(results: [], navigationPath: .constant(NavigationPath()))
            .environmentObject(AuditLogService())
    }
}
