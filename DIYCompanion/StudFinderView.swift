import SwiftUI

struct StudFinderView: View {
    @StateObject private var manager = MagnetometerManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("Sweep slowly along a wall. Spikes indicate studs, screws, or wiring.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.06), lineWidth: 26)
                        .frame(width: 240, height: 240)

                    Circle()
                        .trim(from: 0, to: min(manager.strength / 400.0, 1.0))
                        .stroke(
                            LinearGradient(
                                colors: [threatColor.opacity(0.6), threatColor],
                                startPoint: .top, endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 26, lineCap: .round)
                        )
                        .frame(width: 240, height: 240)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: manager.strength)

                    VStack(spacing: 2) {
                        Text("\(Int(manager.strength))")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("µT")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Text(statusLabel)
                    .font(.subheadline).bold()
                    .padding(.vertical, 10).padding(.horizontal, 20)
                    .background(threatColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(threatColor)
                    .animation(.easeInOut, value: manager.threat)
            }
            .padding()
            .navigationTitle("Wall Scanner")
        }
    }

    private var threatColor: Color {
        switch manager.threat {
        case .safe:    return .green
        case .caution: return .orange
        case .danger:  return .red
        }
    }

    private var statusLabel: String {
        switch manager.threat {
        case .safe:    return "Clear — Safe to Drill"
        case .caution: return "Metal Nearby — Proceed Carefully"
        case .danger:  return "Object Detected — Do Not Drill"
        }
    }
}
