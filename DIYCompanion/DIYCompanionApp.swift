import SwiftUI

@main
struct DIYCompanionApp: App {
    @AppStorage("appearance") private var appearance: String = "dark"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        }
    }
}
