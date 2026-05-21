import SwiftUI
import StoreKit

@main
struct DIYCompanionApp: App {
    @AppStorage("appearance")  private var appearance:  String = "dark"
    @AppStorage("launchCount") private var launchCount: Int    = 0

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .onAppear { handleLaunch() }
        }
    }

    private func handleLaunch() {
        launchCount += 1
        // Ask at launch 5 (a few days in) and launch 15 (a couple of weeks in).
        // Apple rate-limits actual prompts to 3 per year regardless of call frequency.
        guard launchCount == 5 || launchCount == 15 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            else { return }
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
