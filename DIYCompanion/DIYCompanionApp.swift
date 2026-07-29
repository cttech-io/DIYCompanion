import SwiftUI
import UIKit

@main
struct DIYCompanionApp: App {
    @AppStorage(Prefs.appearance) private var appearance: String = Prefs.defaultAppearance

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Single source of truth for appearance: drive the window's
                // interface style ourselves, at launch and on every change.
                .onAppear { Self.applyOverrideStyle(appearance) }
                .onChange(of: appearance) { _, newValue in
                    Self.applyOverrideStyle(newValue)
                }
        }
    }

    /// Force every window's interface style to match the chosen appearance.
    /// We deliberately do NOT use the root `.preferredColorScheme`: it is
    /// honoured at launch but SwiftUI drops its runtime updates when the value
    /// changes from a presented sheet (the Settings screen). Worse, mixing the
    /// two made Dark "sticky" — SwiftUI kept re-asserting a stale Dark
    /// preference and cancelled any revert to Light/System. Setting
    /// `overrideUserInterfaceStyle` directly updates the whole hierarchy
    /// (semantic colours included) immediately and in every direction.
    private static func applyOverrideStyle(_ raw: String) {
        let style: UIUserInterfaceStyle
        switch AppAppearance(rawValue: raw) {
        case .light: style = .light
        case .dark:  style = .dark
        default:     style = .unspecified   // System: follow the OS.
        }
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = style }
    }
}
