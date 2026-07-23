import AppKit
import SwiftUI

struct CleanFlowView: View {
    let results: [ScanResult]

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .confirm
    @State private var outcome: CleanupService.Outcome?
    @State private var showConfirmation = false

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
                ProgressView("Moving to Trash…")
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
                    dismiss()
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
            Text("Freed \(ByteCountFormatter.string(fromByteCount: outcome?.freedBytes ?? 0, countStyle: .file))")
                .font(.title.weight(.semibold))
            Text("\(outcome?.itemCount ?? 0) items moved to Trash")
                .foregroundStyle(.secondary)
            Text("(Scaffold — no files were moved yet.)")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                Button("Open Trash") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash"))
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func performClean() async {
        phase = .working
        do {
            outcome = try await cleanup.moveToTrash(results)
            phase = .done
        } catch {
            phase = .confirm
        }
    }
}

#Preview {
    NavigationStack {
        CleanFlowView(results: [])
    }
}
