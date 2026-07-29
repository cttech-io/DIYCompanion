import SwiftUI
import UIKit

@main
struct DIYCompanionApp: App {
    @AppStorage(Prefs.appearance) private var appearance: String = Prefs.defaultAppearance

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Keep this for a flash-free initial paint. It is honoured at
                // launch but SwiftUI does not reliably re-apply it to the live
                // window when the value changes at runtime from a sheet (the
                // Settings screen), so the override below drives live changes.
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .onChange(of: appearance) { _, newValue in
                    Self.applyOverrideStyle(newValue)
                }
        }
    }

    /// Force the active window's interface style to match the chosen appearance.
    /// Setting `overrideUserInterfaceStyle` updates the whole hierarchy (semantic
    /// colours included) immediately, even from a presented sheet — unlike the
    /// root `preferredColorScheme`, whose runtime updates SwiftUI can drop.
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
