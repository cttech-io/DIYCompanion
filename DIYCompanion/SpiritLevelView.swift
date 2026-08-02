import SwiftUI

struct SpiritLevelView: View {
    @StateObject private var manager = LevelManager()
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        NavigationStack {
            Group {
                if vSize == .compact {
                    HStack(spacing: 32) {
                        levelDisplay(size: 200)
                        VStack(spacing: 0) {
                            Spacer()
                            readouts
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 32)
                } else {
                    VStack(spacing: 32) {
                        Text(manager.isPlumbMode
                            ? "Hold the phone upright against a wall or frame.\nHaptics fire when perfectly plumb."
                            : "Place your phone flat against a surface.\nHaptics fire when perfectly level.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .animation(.easeInOut, value: manager.isPlumbMode)

                        levelDisplay(size: 280)
                        readouts
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
            .navigationTitle("Spirit Level")
            .navigationBarTitleDisplayMode(.inline)
            .withSettingsToolbar()
        }
        .keepsScreenAwake()
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
    }

    // Switch presentation based on how the phone is held: a flat bubble level on
    // a surface, or a plumb tube when held vertically (where attitude pitch/roll
    // hit gimbal lock and can't drive a meaningful bubble).
    @ViewBuilder
    private func levelDisplay(size: CGFloat) -> some View {
        if manager.isPlumbMode {
            PlumbTube(angle: manager.plumbAngle, isLevel: manager.isLevel)
                .frame(width: size, height: size * 0.42)
                .frame(height: size)   // keep the layout slot the same height as the bubble
        } else {
            BubbleLevel(
                pitch: manager.pitch,
                roll: manager.roll,
                isLevel: manager.isLevel,
                orientation: manager.deviceOrientation
            )
            .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private var readouts: some View {
        Group {
            if manager.isPlumbMode {
                AngleReadout(label: "TILT", degrees: manager.plumbAngle)
                    .frame(minWidth: 120)
            } else {
                HStack(spacing: 48) {
                    AngleReadout(label: "PITCH", degrees: manager.pitch)
                    AngleReadout(label: "ROLL",  degrees: manager.roll)
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct BubbleLevel: View {
    let pitch: Double
    let roll: Double
    let isLevel: Bool
    let orientation: UIDeviceOrientation

    // Map device motion axes to screen axes based on current orientation.
    // SwiftUI rotates the view in landscape, but CoreMotion axes stay fixed
    // in device-frame, so we remap here to keep the bubble physically correct.
    private var mappedDx: Double {
        switch orientation {
        case .landscapeLeft:  return  pitch / 15.0
        case .landscapeRight: return -pitch / 15.0
        default:              return  roll  / 15.0
        }
    }

    private var mappedDy: Double {
        switch orientation {
        case .landscapeLeft:  return -roll  / 15.0
        case .landscapeRight: return  roll  / 15.0
        default:              return  pitch / 15.0
        }
    }

    var body: some View {
        GeometryReader { geo in
            let c  = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r  = geo.size.width / 2 - 28
            let dx = CGFloat(max(-1, min(mappedDx, 1))) * r
            let dy = CGFloat(max(-1, min(mappedDy, 1))) * r

            ZStack {
                Circle()
                    .stroke(isLevel ? Color.green : Color.primary.opacity(0.15), lineWidth: 3)
                    .animation(.snappy, value: isLevel)

                Circle()
                    .stroke(isLevel ? Color.green : Color.primary.opacity(0.30), lineWidth: 1.5)
                    .frame(width: 52, height: 52)

                Path { path in
                    path.move(to: CGPoint(x: c.x, y: 8))
                    path.addLine(to: CGPoint(x: c.x, y: geo.size.height - 8))
                    path.move(to: CGPoint(x: 8, y: c.y))
                    path.addLine(to: CGPoint(x: geo.size.width - 8, y: c.y))
                }
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)

                Circle()
                    .fill(isLevel ? Color.green : Color.accentColor)
                    .frame(width: 42, height: 42)
                    .shadow(color: (isLevel ? Color.green : Color.accentColor).opacity(0.6), radius: 12)
                    .position(x: c.x + dx, y: c.y - dy)
                    .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.68), value: dx)
                    .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.68), value: dy)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spirit level")
        .accessibilityValue("Pitch \(String(format: "%.1f", pitch))°, roll \(String(format: "%.1f", roll))°. \(isLevel ? "Level" : "Not level").")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// Single-axis tube level for checking verticality (plumb). The bubble slides
// horizontally as the phone leans off-plumb; centred and green means plumb.
private struct PlumbTube: View {
    let angle: Double
    let isLevel: Bool

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width / 2 - 34
            let dx = CGFloat(max(-1, min(angle / 15.0, 1))) * maxOffset

            ZStack {
                Capsule()
                    .fill(Color(.tertiarySystemBackground))
                Capsule()
                    .stroke(isLevel ? Color.green : Color.primary.opacity(0.15), lineWidth: 3)
                    .animation(.snappy, value: isLevel)

                // Centre target the bubble should sit between when plumb.
                HStack(spacing: 46) {
                    Capsule().frame(width: 2)
                    Capsule().frame(width: 2)
                }
                .frame(height: geo.size.height * 0.55)
                .foregroundStyle(Color.primary.opacity(isLevel ? 0.0 : 0.18))

                Circle()
                    .fill(isLevel ? Color.green : Color.accentColor)
                    .frame(width: 46, height: 46)
                    .shadow(color: (isLevel ? Color.green : Color.accentColor).opacity(0.6), radius: 12)
                    .offset(x: dx)
                    .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.68), value: dx)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plumb level")
        .accessibilityValue("\(String(format: "%.1f", abs(angle)))° from vertical. \(isLevel ? "Plumb" : "Not plumb").")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct AngleReadout: View {
    let label: String
    let degrees: Double

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2).bold().foregroundStyle(.secondary)
            Text(String(format: "%.1f°", degrees))
                .font(.title3).bold().monospacedDigit()
        }
    }
}
