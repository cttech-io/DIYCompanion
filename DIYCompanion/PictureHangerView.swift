import SwiftUI

struct PictureHangerView: View {
    @StateObject private var manager = LevelManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("Place your phone flat against a surface.\nHaptics fire when perfectly level.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                BubbleLevel(pitch: manager.pitch, roll: manager.roll, isLevel: manager.isLevel)
                    .frame(width: 280, height: 280)

                HStack(spacing: 48) {
                    AngleReadout(label: "PITCH", degrees: manager.pitch)
                    AngleReadout(label: "ROLL",  degrees: manager.roll)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
            .navigationTitle("Picture Hanger")
        }
    }
}

private struct BubbleLevel: View {
    let pitch: Double
    let roll: Double
    let isLevel: Bool

    var body: some View {
        GeometryReader { geo in
            let c  = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r  = geo.size.width / 2 - 28
            let dx = CGFloat(max(-1, min(roll  / 15.0, 1))) * r
            let dy = CGFloat(max(-1, min(pitch / 15.0, 1))) * r

            ZStack {
                Circle()
                    .stroke(isLevel ? Color.green : Color.primary.opacity(0.12), lineWidth: 3)
                    .animation(.snappy, value: isLevel)

                Circle()
                    .stroke(isLevel ? Color.green : Color.primary.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 52, height: 52)

                Path { path in
                    path.move(to: CGPoint(x: c.x, y: 8))
                    path.addLine(to: CGPoint(x: c.x, y: geo.size.height - 8))
                    path.move(to: CGPoint(x: 8, y: c.y))
                    path.addLine(to: CGPoint(x: geo.size.width - 8, y: c.y))
                }
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)

                Circle()
                    .fill(isLevel ? Color.green : Color.accentColor)
                    .frame(width: 42, height: 42)
                    .shadow(radius: 6)
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
