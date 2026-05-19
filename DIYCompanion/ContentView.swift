import SwiftUI

// Resolves once at launch. British English variants use "Torch"; US English uses "Flashlight".
let flashlightName: String = {
    let lang = Locale.preferredLanguages.first ?? ""
    let britishEnglish = ["en-GB", "en-AU", "en-NZ", "en-IE", "en-IN", "en-ZA"]
    return britishEnglish.contains(where: { lang.hasPrefix($0) }) ? "Torch" : "Flashlight"
}()

struct ContentView: View {
    var body: some View {
        TabView {
            SpiritLevelView()
                .tabItem {
                    Label("Spirit Level", systemImage: "level")
                }

            Group {
                #if targetEnvironment(simulator)
                ContentUnavailableView(
                    "Hardware Required",
                    systemImage: "cpu",
                    description: Text("Wall Scanner requires a physical device with a magnetometer.")
                )
                #else
                StudFinderView()
                #endif
            }
            .tabItem {
                Label("Wall Scanner", systemImage: "waveform.path.ecg")
            }

            InspectionLightView()
                .tabItem {
                    Label(flashlightName, systemImage: "flashlight.on.fill")
                }
        }
    }
}
