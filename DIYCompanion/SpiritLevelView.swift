import SwiftUI

struct SpiritLevelView: View {
    @StateObject private var manager = LevelManager()
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        NavigationStack {
            Group {
                if vSize == .compact {
                    HStack(spacing: 32) {
                        BubbleLevel(
                            pitch: manager.pitch,
                            roll: manager.roll,
                            isLevel: manager.isLevel,
                            orientation: manager.deviceOrientation
                        )
                        .frame(width: 200, height: 200)

                        VStack(spacing: 0) {
                            Spacer()
                            HStack(spacing: 40) {
                                AngleReadout(label: "PITCH", degrees: manager.pitch)
                                AngleReadout(label: "ROLL",  degrees: manager.roll)
                            }
                            .padding()
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 32)
                } else {
                    VStack(spacing: 32) {
                        Text("Place your phone flat against a surface.\nHaptics fire when perfectly level.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        BubbleLevel(
                            pitch: manager.pitch,
                            roll: manager.roll,
                            isLevel: manager.isLevel,
                            orientation: manager.deviceOrientation
                        )
                        .frame(width: 280, height: 280)

                        HStack(spacing: 48) {
                            AngleReadout(label: "PITCH", degrees: manager.pitch)
                            AngleReadout(label: "ROLL",  degrees: manager.roll)
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
            .navigationTitle("Spirit Level")
            .navigationBarTitleDisplayMode(.automatic)
        }
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
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
                    .stroke(isLevel ? Color.green : Color.white.opacity(0.15), lineWidth: 3)
                    .animation(.snappy, value: isLevel)

                Circle()
                    .stroke(isLevel ? Color.green : Color.white.opacity(0.30), lineWidth: 1.5)
                    .frame(width: 52, height: 52)

                Path { path in
                    path.move(to: CGPoint(x: c.x, y: 8))
                    path.addLine(to: CGPoint(x: c.x, y: geo.size.height - 8))
                    path.move(to: CGPoint(x: 8, y: c.y))
                    path.addLine(to: CGPoint(x: geo.size.width - 8, y: c.y))
                }
                .stroke(Color.white.opacity(0.08), lineWidth: 1)

                Circle()
                    .fill(isLevel ? Color.green : Color.accentColor)
                    .frame(width: 42, height: 42)
                    .shadow(color: (isLevel ? Color.green : Color.accentColor).opacity(0.6), radius: 12)
                    .position(x: c.x + dx, y: c.y - dy)
                    .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.68), value: dx)
                    .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.68), value: dy)
            }
        }
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
