import SwiftUI

struct InspectionLightView: View {
    @StateObject private var manager = TorchManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Text("Fine control for inspecting dark spaces under stairs, behind panels, or in ceiling voids.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    manager.intensity = manager.intensity > 0 ? 0 : 1.0
                } label: {
                    ZStack {
                        Circle()
                            .fill(manager.intensity > 0 ? Color.yellow.opacity(0.15) : Color.primary.opacity(0.06))
                            .frame(width: 150, height: 150)
                        Image(systemName: "flashlight.on.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(manager.intensity > 0 ? .yellow : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .animation(.snappy, value: manager.intensity > 0)

                VStack(spacing: 12) {
                    HStack {
                        Text("Beam Intensity")
                            .font(.caption).bold().foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(manager.intensity * 100))%")
                            .font(.caption).bold().monospacedDigit()
                    }
                    Slider(value: $manager.intensity, in: 0...1, step: 0.05)
                        .tint(.yellow)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Inspection Light")
        }
    }
}
