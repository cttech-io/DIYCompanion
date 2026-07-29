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

    var body: some View {
        TabView {
            SpiritLevelView()
                .tabItem {
                    Label("Spirit Level", systemImage: "level")
                }

            StudFinderView()
                .tabItem {
                    Label("Wall Scanner", systemImage: "waveform.path.ecg")
                }

            InspectionLightView()
                .tabItem {
                    Label(flashlightName, systemImage: "flashlight.on.fill")
                }

            NoiseMeterView()
                .tabItem {
                    Label("Noise Meter", systemImage: "waveform")
                }

            RulerView()
                .tabItem {
                    Label("Ruler", systemImage: "ruler")
                }
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
