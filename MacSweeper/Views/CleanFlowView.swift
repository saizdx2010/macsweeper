import AppKit
import SwiftUI

struct CleanFlowView: View {
    let results: [ScanResult]

    @State private var phase: Phase = .confirm
    @State private var outcome: CleanupService.Outcome?

    private let cleanup = CleanupService()

    private var totalBytes: Int64 {
        results.reduce(0) { $0 + $1.totalBytes }
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
    }

    private var confirmView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to clean \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
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
                Spacer()
                Button("Move to Trash") {
                    Task { await performClean() }
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
