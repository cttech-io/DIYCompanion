import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            PictureHangerView()
                .tabItem {
                    Label("Level", systemImage: "level")
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
                    Label("Torch", systemImage: "flashlight.on.fill")
                }
        }
    }
}
