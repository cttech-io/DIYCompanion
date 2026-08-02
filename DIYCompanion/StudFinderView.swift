import SwiftUI

struct StudFinderView: View {
    @StateObject private var manager = MagnetometerManager()
    @Environment(\.verticalSizeClass) private var vSize
    @AppStorage(Prefs.studFinderDisclaimerAccepted) private var disclaimerAccepted = false
    @State private var showDisclaimer = false

    var body: some View {
        NavigationStack {
            Group {
                if vSize == .compact {
                    HStack(spacing: 24) {
                        gaugeRing(size: 160)
                        VStack(spacing: 16) {
                            Spacer()
                            statusChip
                            sensitivityCard
                            calibrateCard
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 32)
                } else {
                    GeometryReader { proxy in
                        ScrollView {
                            VStack(spacing: 24) {
                                hintText
                                gaugeRing(size: 240)
                                statusChip
                                sensitivityCard
                                    .padding(.horizontal)
                                calibrateCard
                                    .padding(.horizontal)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
            .navigationTitle("Wall Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .withSettingsToolbar()
        }
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerSheet {
                disclaimerAccepted = true
                showDisclaimer = false
            }
            .interactiveDismissDisabled()
        }
        .keepsScreenAwake()
        .onAppear {
            manager.start()
            if !disclaimerAccepted { showDisclaimer = true }
        }
        .onDisappear { manager.stop() }
    }

    // Arc fill scales with sensitivity so the slider has immediate visual impact.
    // Deviation is measured from the calibrated baseline, so the gauge reads near
    // zero in free air regardless of Earth's field or the phone's own magnetic bias.
    private func gaugeRing(size: CGFloat) -> some View {
        let strokeWidth = size * 0.108
        let fontSize    = size * 0.217

        return ZStack {
            Circle()
                .stroke(Color(.systemFill), lineWidth: strokeWidth)
                .frame(width: size, height: size)

            if !manager.isCalibrating {
                Circle()
                    .trim(from: 0, to: min(manager.deviation * manager.sensitivity / 100.0, 1.0))
                    .stroke(
                        LinearGradient(
                            colors: [threatColor.opacity(0.6), threatColor],
                            startPoint: .top, endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: manager.deviation)
            }

            if manager.isCalibrating {
                VStack(spacing: 6) {
                    ProgressView()
                        .tint(.secondary)
                    Text("Calibrating")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 2) {
                    Text("\(Int(manager.deviation))")
                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("µT")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Metal detection gauge")
        .accessibilityValue(manager.isCalibrating
            ? "Calibrating, hold phone away from walls"
            : "\(Int(manager.deviation)) microteslas. \(statusLabel).")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var hintText: some View {
        VStack(spacing: 8) {
            Text("Sweep slowly along a wall. Spikes indicate studs, screws, or wiring.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Label("Remove MagSafe accessories and calibrate before use.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var statusChip: some View {
        if manager.isCalibrating {
            VStack(spacing: 8) {
                Text("Hold phone away from walls")
                    .font(.subheadline).bold()
                    .padding(.vertical, 10).padding(.horizontal, 20)
                    .background(Color(.systemFill), in: Capsule())
                    .foregroundStyle(.secondary)
                Label("Remove MagSafe accessories", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        } else {
            Text(statusLabel)
                .font(.subheadline).bold()
                .padding(.vertical, 10).padding(.horizontal, 20)
                .background(threatColor.opacity(0.18), in: Capsule())
                .foregroundStyle(threatColor)
                .animation(.easeInOut, value: manager.threat)
        }
    }

    private var sensitivityCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Sensitivity")
                    .font(.caption).bold().foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1fx", manager.sensitivity))
                    .font(.caption).bold().monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("Low").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $manager.sensitivity, in: 0.5...2.0)
                    .tint(.accentColor)
                    .accessibilityLabel("Sensitivity")
                Text("High").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var calibrateCard: some View {
        Button {
            manager.recalibrate()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    if manager.isCalibrating {
                        ProgressView()
                            .tint(.accentColor)
                    } else {
                        Image(systemName: "scope")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text("Calibrate Sensor")
                    .font(.subheadline).bold()
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(manager.isCalibrating)
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
        case .safe:    return "No Metal Detected"
        case .caution: return "Metal Nearby — Proceed Carefully"
        case .danger:  return "Object Detected — Do Not Drill"
        }
    }
}

private struct DisclaimerSheet: View {
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            VStack(spacing: 10) {
                Text("Important Disclaimer")
                    .font(.title3).bold()

                Text("This scanner is a general guide only and **cannot guarantee accuracy**. Always confirm stud, pipe, and wiring locations with a professional-grade detector before drilling. DIY Companion accepts no liability for any damage or injury resulting from use of this feature.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onAccept) {
                Text("I Understand — Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
        }
        .padding(28)
        .presentationDetents([.medium])
    }
}
