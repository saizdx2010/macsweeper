import SwiftUI

struct ScanResultsView: View {
    @ObservedObject var session: ScanSession
    let includeDevMode: Bool
    @Binding var path: NavigationPath

    @State private var cardsVisible = false

    private var selectedBytes: Int64 { session.selectedBytes }
    private var totalBytes: Int64 { session.totalBytes }

    var body: some View {
        ZStack {
            StageBackground()

            VStack(spacing: 0) {
                content

                footerBar
            }
        }
        .appDestinationChrome(
            title: titleText,
            subtitle: selectedSubtitle,
            onBack: { AppNavigation.popToRoot($path) }
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Rescan") {
                    path = NavigationPath()
                    path.append(AppRoute.scanning)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(0.05)) {
                cardsVisible = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .failed(let message):
            ContentUnavailableView(
                "Scan failed",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .cancelled where session.results.isEmpty:
            ContentUnavailableView(
                "Scan cancelled",
                systemImage: "stop.circle",
                description: Text("No categories finished before cancel.")
            )
        case _ where session.results.isEmpty:
            ContentUnavailableView(
                "No reclaimable space found",
                systemImage: "tray",
                description: Text(
                    "Checked \(session.loadedRuleCount) rules under your home folder. Nothing matched with measurable size."
                )
            )
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: MSTheme.sectionSpacing) {
                    headerBand
                        .opacity(cardsVisible ? 1 : 0)

                    if !session.coreIndices.isEmpty {
                        section(title: "Reclaimable", indices: session.coreIndices)
                    }

                    if !session.devIndices.isEmpty {
                        section(title: "Dev", indices: session.devIndices)
                    }

                    Text("Sizes are approximate (allocated disk use; hard links counted once).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(MSTheme.pagePadding)
            }
        }
    }

    private var headerBand: some View {
        MSCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(MSTheme.accent)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.2), value: selectedBytes)
                }
            }
        }
    }

    private func section(title: String, indices: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ForEach(Array(indices.enumerated()), id: \.element) { offset, index in
                CategoryCardRow(
                    result: $session.results[index],
                    showsSelection: true,
                    showsChevron: true,
                    onDetails: {
                        path.append(AppRoute.detail(session.results[index]))
                    }
                )
                .opacity(cardsVisible ? 1 : 0)
                .offset(y: cardsVisible ? 0 : 8)
                .animation(
                    .easeOut(duration: 0.3).delay(Double(offset) * 0.03),
                    value: cardsVisible
                )
            }
        }
    }

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 16) {
                Text("Selected \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: selectedBytes)

                Spacer(minLength: 8)

                PrimaryCTANavigationLink(
                    title: "Clean Now",
                    value: AppRoute.clean(session.selectedResults),
                    isEnabled: !session.selectedResults.isEmpty
                )
                .frame(maxWidth: 200)
            }
            .padding(.horizontal, MSTheme.pagePadding)
            .padding(.vertical, 14)
            .background(MSTheme.canvas.opacity(0.95))
        }
    }

    private var titleText: String {
        if session.results.isEmpty {
            return "Results"
        }
        return "Found \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
    }

    private var selectedSubtitle: String {
        "Selected \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))"
    }
}

#Preview {
    NavigationStack {
        ScanResultsView(
            session: ScanSession(),
            includeDevMode: false,
            path: .constant(NavigationPath())
        )
    }
}
