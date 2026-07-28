import SwiftUI

enum AppNavigation {
    /// Pops one destination if present.
    static func popLast(_ path: Binding<NavigationPath>) {
        guard !path.wrappedValue.isEmpty else { return }
        path.wrappedValue.removeLast()
    }

    /// Clears the stack back to Home.
    static func popToRoot(_ path: Binding<NavigationPath>) {
        path.wrappedValue = NavigationPath()
    }
}

/// Shared navigation chrome for pushed screens so Back is always available on macOS.
struct AppDestinationChrome: ViewModifier {
    let title: String
    var subtitle: String? = nil
    var showsBack: Bool = true
    let onBack: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            #if os(macOS)
            .modifier(OptionalNavigationSubtitle(subtitle: subtitle))
            #endif
            // Always use our explicit Back — system back is unreliable with custom toolbars on macOS.
            .navigationBarBackButtonHidden(true)
            .toolbar(.visible, for: .windowToolbar)
            .toolbar {
                if showsBack {
                    ToolbarItem(placement: .navigation) {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.backward")
                                    .font(.body.weight(.semibold))
                                Text("Back")
                            }
                        }
                        .help("Back")
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Back")
                    }
                }
            }
    }
}

#if os(macOS)
private struct OptionalNavigationSubtitle: ViewModifier {
    let subtitle: String?

    func body(content: Content) -> some View {
        if let subtitle, !subtitle.isEmpty {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}
#endif

extension View {
    func appDestinationChrome(
        title: String,
        subtitle: String? = nil,
        showsBack: Bool = true,
        onBack: @escaping () -> Void
    ) -> some View {
        modifier(
            AppDestinationChrome(
                title: title,
                subtitle: subtitle,
                showsBack: showsBack,
                onBack: onBack
            )
        )
    }
}
