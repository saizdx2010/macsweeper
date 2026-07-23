import SwiftUI

/// Full-bleed scanning theater driven by a shared `ScanSession`.
struct ScanningView: View {
    @ObservedObject var session: ScanSession
    let includeDevMode: Bool
    @Binding var path: NavigationPath

    @State private var ringDrawn = false
    @State private var didStart = false

    private var canGoBack: Bool {
        session.phase != .scanning
    }

    var body: some View {
        ZStack {
            StageBackground()

            VStack(spacing: 28) {
                Spacer()

                DiskRingView(
                    usedFraction: ringDrawn ? session.progressFraction : 0,
                    lineWidth: MSTheme.heroRingLineWidth,
                    size: MSTheme.heroRingSize,
                    progressColor: MSTheme.accent
                ) {
                    VStack(spacing: 6) {
                        Text(progressLabel)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: session.scannedRuleCount)
                        Text("scanned")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: session.progressFraction)

                VStack(spacing: 8) {
                    Text(headline)
                        .font(MSTheme.titleFont)
                    Text(session.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                        .animation(.easeInOut(duration: 0.2), value: session.statusMessage)
                }

                if session.phase == .scanning {
                    Button("Cancel") {
                        session.cancel()
                    }
                    .keyboardShortcut(.cancelAction)
                } else if session.phase == .cancelled || isFailed {
                    VStack(spacing: 12) {
                        if case .failed(let message) = session.phase {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 360)
                        }
                        PrimaryCTAButton(title: "Back to Home") {
                            AppNavigation.popToRoot($path)
                        }
                        .frame(maxWidth: 280)
                    }
                }

                Spacer()
            }
            .padding(MSTheme.pagePadding)
        }
        .appDestinationChrome(
            title: "Scan",
            showsBack: canGoBack,
            onBack: { AppNavigation.popToRoot($path) }
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                ringDrawn = true
            }
            guard !didStart else { return }
            didStart = true
            session.start(includeDevMode: includeDevMode)
        }
        .onChange(of: session.phase) { _, newPhase in
            guard newPhase == .finished else { return }
            // Replace theater with results (Home remains under the stack).
            path = NavigationPath()
            path.append(AppRoute.results)
        }
    }

    private var isFailed: Bool {
        if case .failed = session.phase { return true }
        return false
    }

    private var headline: String {
        switch session.phase {
        case .scanning, .idle:
            return "Scanning your Mac"
        case .finished:
            return "Scan complete"
        case .cancelled:
            return "Scan cancelled"
        case .failed:
            return "Scan failed"
        }
    }

    private var progressLabel: String {
        if session.loadedRuleCount > 0 {
            return "\(Int((session.progressFraction * 100).rounded()))%"
        }
        return "…"
    }
}

#Preview {
    NavigationStack {
        ScanningView(
            session: ScanSession(),
            includeDevMode: false,
            path: .constant(NavigationPath())
        )
    }
}
