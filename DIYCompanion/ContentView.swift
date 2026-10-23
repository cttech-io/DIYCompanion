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

/// Decides when to ask for a rating. Asking at launch put the prompt over a
/// tool the user had just opened to work with; instead we count completed
/// tasks (the level settling green, a ruler measurement copied) and ask at a
/// natural pause — the next tab switch after one — once enough have happened.
enum ReviewGate {
    /// Successes needed before each ask. Apple caps actual prompts at three a
    /// year regardless, so two well-timed asks is plenty.
    static let milestones = [3, 15]

    static func shouldPrompt(successes: Int, promptsShown: Int) -> Bool {
        promptsShown < milestones.count && successes >= milestones[promptsShown]
    }

    /// A success since the last tab switch, so the ask lands right after one.
    private(set) static var hasPendingSuccess = false

    static func recordSuccess(defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: Prefs.successCount) + 1, forKey: Prefs.successCount)
        hasPendingSuccess = true
    }

    /// Consumes the pending success; true when a prompt should be shown now.
    static func takePromptDecision(defaults: UserDefaults = .standard) -> Bool {
        guard hasPendingSuccess else { return false }
        hasPendingSuccess = false
        let shown = defaults.integer(forKey: Prefs.reviewPromptsShown)
        guard shouldPrompt(successes: defaults.integer(forKey: Prefs.successCount),
                           promptsShown: shown) else { return false }
        defaults.set(shown + 1, forKey: Prefs.reviewPromptsShown)
        return true
    }
}

struct ContentView: View {
    @Environment(\.requestReview) private var requestReview

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
        .onChange(of: selectedTab) { _, _ in
            // Moving to another tool is the pause after a finished task.
            guard ReviewGate.takePromptDecision() else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                requestReview()
            }
        }
    }
}
