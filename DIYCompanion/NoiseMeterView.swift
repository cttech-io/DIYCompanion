import SwiftUI

struct NoiseMeterView: View {
    @StateObject private var manager = NoiseManager()
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if manager.permissionDenied {
                    ContentUnavailableView {
                        Label("Microphone Access Required", systemImage: "mic.slash")
                    } description: {
                        Text("The Noise Meter needs the microphone to measure sound levels.")
                    } actions: {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if vSize == .compact {
                    HStack(spacing: 24) {
                        gaugeRing(size: 160)
                        VStack(spacing: 16) {
                            Spacer()
                            statusChip
                            peakCard
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 32)
                } else {
                    VStack(spacing: 24) {
                        Text("Hold near a sound source to measure ambient noise level.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        gaugeRing(size: 240)
                        statusChip
                        peakCard
                            .padding(.horizontal)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
            .navigationTitle("Noise Meter")
            .navigationBarTitleDisplayMode(.automatic)
            .withSettingsToolbar()
        }
        .keepsScreenAwake()
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
        .onChange(of: scenePhase) { _, phase in
            // On return to foreground: recover a recorder an interruption killed,
            // and pick up a mic permission granted in Settings while we were away.
            if phase == .active { manager.restartIfNeeded() }
        }
    }

    private func gaugeRing(size: CGFloat) -> some View {
        let strokeWidth = size * 0.108
        let fontSize    = size * 0.217
        let fraction    = CGFloat((manager.decibels - 30) / 90)  // maps 30–120 dB → 0–1

        return ZStack {
            Circle()
                .stroke(Color(.systemFill), lineWidth: strokeWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: min(fraction, 1.0))
                .stroke(
                    LinearGradient(
                        colors: [tierColor.opacity(0.6), tierColor],
                        startPoint: .top, endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: manager.decibels)

            VStack(spacing: 2) {
                Text(String(format: "%.0f", manager.decibels))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("dB SPL")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Noise level gauge")
        .accessibilityValue("\(Int(manager.decibels)) decibels. \(tierLabel).")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var statusChip: some View {
        Text(tierLabel)
            .font(.subheadline).bold()
            .padding(.vertical, 10).padding(.horizontal, 20)
            .background(tierColor.opacity(0.18), in: Capsule())
            .foregroundStyle(tierColor)
            .animation(.easeInOut, value: manager.tier)
    }

    private var peakCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Peak Level")
                    .font(.caption).bold().foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f dB", manager.peak))
                    .font(.caption).bold().monospacedDigit()
            }
            Button("Reset Peak") { manager.resetPeak() }
                .font(.caption)
                .tint(.accentColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var tierColor: Color {
        switch manager.tier {
        case .quiet:     return .green
        case .moderate:  return .yellow
        case .loud:      return .orange
        case .dangerous: return .red
        }
    }

    private var tierLabel: String {
        switch manager.tier {
        case .quiet:     return "Quiet"
        case .moderate:  return "Moderate"
        case .loud:      return "Loud"
        case .dangerous: return "Dangerous"
        }
    }
}
