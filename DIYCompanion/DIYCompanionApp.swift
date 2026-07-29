import SwiftUI

@main
struct DIYCompanionApp: App {
    @AppStorage(Prefs.appearance) private var appearance: String = Prefs.defaultAppearance

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        }
    }
}
