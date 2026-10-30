import SwiftUI

/// Full-bleed scanning theater driven by a shared `ScanSession`.
struct ScanningView: View {
    @ObservedObject var session: ScanSession
    let includeDevMode: Bool
    var extraDevRoots: [String] = []
    @Binding var path: NavigationPath

    @State private var ringDrawn = false
    @State private var didStart = false

    private var canGoBack: Bool {
        session.phase != .scanning
    }

    var body: some View {
        ZStack {
            StageBackground()

            VStack(spacing: 0) {
                Spacer()

                ScanSweepRing(
                    progress: ringDrawn ? session.progressFraction : 0,
                    isActive: session.phase == .scanning || session.phase == .idle
                ) {
                    VStack(spacing: 4) {
                        Text(progressLabel)
                            .font(MSTheme.displayFont)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(MSMotion.fast, value: session.scannedRuleCount)
                        Text("scanned")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(MSMotion.base, value: session.progressFraction)

                VStack(spacing: 6) {
                    Text(headline)
                        .font(MSTheme.titleFont)
                    Text(session.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: 380, minHeight: 36, alignment: .top)
                        .contentTransition(.opacity)
                        .animation(MSMotion.fast, value: session.statusMessage)
                }
                .padding(.top, 26)

                Group {
                    if session.phase == .scanning {
                        SecondaryCTAButton(title: "Cancel", expands: false) {
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
                            PrimaryCTAButton(title: "Back to Home", expands: false) {
                                AppNavigation.popToRoot($path)
                            }
                        }
                    }
                }
                .padding(.top, 18)

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
            withAnimation(MSMotion.slow) {
                ringDrawn = true
            }
            guard !didStart else { return }
            didStart = true
            session.start(includeDevMode: includeDevMode, extraDevRoots: extraDevRoots)
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
