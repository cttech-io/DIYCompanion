import Foundation

/// Centralised `UserDefaults` / `@AppStorage` keys so a typo can't silently
/// fork a setting across files.
enum Prefs {
    static let appearance = "appearance"
    static let useMetric = "useMetric"
    static let hapticsEnabled = "hapticsEnabled"
    static let launchCount = "launchCount"
    static let studFinderDisclaimerAccepted = "studFinderDisclaimerAccepted"

    /// User-calibrated points-per-inch for the ruler. Zero means "not
    /// calibrated" — fall back to the per-model physical density. Needed on
    /// iPad, where iPhone-compatibility-mode scaling makes the density unknown.
    static let rulerCalibratedPPI = "rulerCalibratedPPI"

    /// Default theme: honour the system appearance. An in-app override is opt-in.
    static let defaultAppearance = "system"
}
