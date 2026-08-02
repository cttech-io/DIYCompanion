import SwiftUI

struct InspectionLightView: View {
    @StateObject private var manager = TorchManager()
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if vSize == .compact {
                    HStack(spacing: 32) {
                        torchButton(size: 110)
                        VStack(spacing: 0) {
                            Spacer()
                            intensityCard
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 32)
                } else {
                    VStack(spacing: 40) {
                        Text("Fine control for inspecting dark spaces under stairs, behind panels, or in ceiling voids.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        torchButton(size: 150)
                        intensityCard
                            .padding(.horizontal)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
            .navigationTitle(flashlightName)
            .navigationBarTitleDisplayMode(.inline)
            .withSettingsToolbar()
        }
        .keepsScreenAwake()
        .onDisappear { manager.stop() }
        .onChange(of: scenePhase) { _, phase in
            // iOS force-disables the torch when the app backgrounds; mirror that
            // in our model so the button/slider don't claim it's still on (which
            // otherwise needs a wasted "off" tap to resync on return).
            if phase == .background { manager.stop() }
        }
    }

    private func torchButton(size: CGFloat) -> some View {
        Button {
            manager.intensity = manager.intensity > 0 ? 0 : 1.0
        } label: {
            ZStack {
                Circle()
                    .fill(manager.intensity > 0 ? Color.yellow.opacity(0.15) : Color(.systemFill))
                    .frame(width: size, height: size)
                Image(systemName: "flashlight.on.fill")
                    .font(.system(size: size * 0.333))
                    .foregroundStyle(manager.intensity > 0 ? .yellow : .secondary)
                    .shadow(color: manager.intensity > 0 ? Color.yellow.opacity(0.7) : .clear, radius: 16)
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: manager.intensity > 0)
        .accessibilityLabel("Torch")
        .accessibilityValue(manager.intensity > 0 ? "On, \(Int(manager.intensity * 100)) percent" : "Off")
        .accessibilityHint("Double tap to toggle")
    }

    private var intensityCard: some View {
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
                .accessibilityLabel("Beam intensity")
        }
        .padding(20)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
