import SwiftUI
import StoreKit

// British English variants use "Torch"; US English uses "Flashlight".
func resolveFlashlightName(for languages: [String] = Locale.preferredLanguages) -> String {
    let lang = languages.first ?? ""
    let britishEnglish = ["en-GB", "en-AU", "en-NZ", "en-IE", "en-IN", "en-ZA"]
    return britishEnglish.contains(where: { lang.hasPrefix($0) }) ? "Torch" : "Flashlight"
}

// Resolves once at launch.
let flashlightName: String = resolveFlashlightName()

struct ContentView: View {
    @AppStorage(Prefs.launchCount) private var launchCount: Int = 0
    @Environment(\.requestReview) private var requestReview

    // Per-process guard: `.task`/`onAppear` can re-fire on scene reconnection,
    // and we must count each app launch exactly once.
    private static var didHandleLaunch = false

    @State private var selectedTab: Int = ContentView.initialTab

    /// Always the first tab on device. In the Simulator, honours DIY_START_TAB
    /// so the screenshot tooling can open a tool directly without needing to
    /// drive the tab bar — see `Screenshots/capture-raw-screenshots.sh`.
    private static var initialTab: Int {
        #if targetEnvironment(simulator)
        if let raw = ProcessInfo.processInfo.environment["DIY_START_TAB"],
           let tab = Int(raw), (0...4).contains(tab) {
            return tab
        }
        #endif
        return 0
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SpiritLevelView()
                .tabItem {
                    Label("Level", systemImage: "level")
                }
                .tag(0)

            StudFinderView()
                .tabItem {
                    Label("Scanner", systemImage: "waveform.path.ecg")
                }
                .tag(1)

            InspectionLightView()
                .tabItem {
                    Label(flashlightName, systemImage: "flashlight.on.fill")
                }
                .tag(2)

            NoiseMeterView()
                .tabItem {
                    Label("Noise", systemImage: "waveform")
                }
                .tag(3)

            RulerView()
                .tabItem {
                    Label("Ruler", systemImage: "ruler")
                }
                .tag(4)
        }
        .task { handleLaunch() }
    }

    private func handleLaunch() {
        guard !Self.didHandleLaunch else { return }
        Self.didHandleLaunch = true

        launchCount += 1
        // Ask at launch 5 (a few days in) and launch 15 (a couple of weeks in).
        // Apple rate-limits actual prompts to 3 per year regardless of call frequency.
        guard launchCount == 5 || launchCount == 15 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            requestReview()
        }
    }
}
