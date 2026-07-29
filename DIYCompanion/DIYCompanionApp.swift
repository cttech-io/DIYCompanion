import SwiftUI

@main
struct DIYCompanionApp: App {
    @AppStorage(Prefs.appearance) private var appearance: String = Prefs.defaultAppearance

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Apply the stored appearance at launch. The live update when the
                // user changes it is applied from SettingsView itself, because an
                // @AppStorage onChange here (outside the Settings sheet) does not
                // fire reliably across the sheet boundary on iOS 18+.
                .onAppear { AppAppearance.apply(appearance) }
        }
    }
}
