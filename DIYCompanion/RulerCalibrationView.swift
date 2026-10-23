import SwiftUI

/// Manual ruler calibration. The user matches an on-screen reference to the
/// long edge of a standard ID-1 bank/credit card (85.60 mm), which pins the
/// screen's true points-per-inch. This is needed on iPad, where iPhone-
/// compatibility mode scales the whole canvas by a factor the app can't read
/// back — so the per-model density estimate no longer holds.
struct RulerCalibrationView: View {
    /// ID-1 card long edge (85.60 mm), in inches.
    static let cardLongEdgeInches: CGFloat = 85.60 / 25.4

    static let minPPI: CGFloat = 50

    /// Slider ceiling for a given drawable middle region. The bar is drawn at
    /// its true length, so the largest scale we can honestly show is whatever
    /// card edge fits the space.
    static func maxPPI(middleHeight: CGFloat) -> CGFloat {
        (middleHeight - 24) / cardLongEdgeInches
    }

    /// Clamps a scale into what the current layout can actually display.
    /// Everything — bar, slider and Save — goes through this, so the value
    /// persisted is always the one the user lined their card up against.
    static func clampedPPI(_ raw: CGFloat, middleHeight: CGFloat) -> CGFloat {
        let ceiling = maxPPI(middleHeight: middleHeight)
        guard ceiling > minPPI else { return max(raw, minPPI) }
        return min(max(raw, minPPI), ceiling)
    }

    let onSave: (CGFloat) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ppi: CGFloat
    /// Mirrors the geometry so the Save action, which sits outside the
    /// GeometryReader, can apply the same clamp the bar was drawn with.
    @State private var middleHeight: CGFloat = 0

    init(pointsPerInch: CGFloat,
         onSave: @escaping (CGFloat) -> Void,
         onReset: @escaping () -> Void) {
        self.onSave = onSave
        self.onReset = onReset
        _ppi = State(initialValue: pointsPerInch)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                // Fixed top/bottom regions leave a bounded middle for the bar, so
                // the instruction always wraps and the slider is always visible.
                // The bar is drawn at its true length, so the slider ceiling is
                // whatever card edge fits the middle region.
                let topReserve: CGFloat = 132
                let bottomReserve: CGFloat = 96
                let middle = max(geo.size.height - topReserve - bottomReserve, 260)
                // Ceiling comes straight from the drawable middle, so the bar
                // (clamped × card edge) can never exceed its region and overlap
                // the instruction or slider. middle ≥ 260 keeps max > min.
                let minPPI = Self.minPPI
                let maxPPI = Self.maxPPI(middleHeight: middle)
                let clamped = Self.clampedPPI(ppi, middleHeight: middle)
                let barHeight = clamped * Self.cardLongEdgeInches

                VStack(spacing: 0) {
                    Text("Line a bank card's long edge against the bar, then drag the slider until the bar's length matches the card exactly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(height: topReserve)
                        .frame(maxWidth: .infinity)

                    HStack(alignment: .center, spacing: 20) {
                        referenceBar(height: barHeight)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Card long edge")
                                .font(.footnote).bold()
                            Text("85.6 mm")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: middle)
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { min(max(ppi, minPPI), maxPPI) },
                                set: { ppi = $0 }
                            ),
                            in: minPPI...maxPPI
                        )
                        .accessibilityLabel("Ruler scale")
                        HStack {
                            Text("Shorter")
                            Spacer()
                            Text("Longer")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .frame(height: bottomReserve)
                }
                .padding(.horizontal)
                // Pull the incoming scale into range straight away, and again if
                // the region resizes (rotation, iPad multitasking) — otherwise
                // the bar would show a clamped value while `ppi` held a
                // different one, and Save would persist the latter.
                .onAppear {
                    middleHeight = middle
                    ppi = Self.clampedPPI(ppi, middleHeight: middle)
                }
                .onChange(of: middle) { _, newMiddle in
                    middleHeight = newMiddle
                    ppi = Self.clampedPPI(ppi, middleHeight: newMiddle)
                }
            }
            .navigationTitle("Calibrate Ruler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.accentText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Save exactly what the bar was drawn at.
                        onSave(Self.clampedPPI(ppi, middleHeight: middleHeight))
                        dismiss()
                    }
                    .bold()
                    .tint(Color.accentText)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset to Default", role: .destructive) {
                        onReset()
                        dismiss()
                    }
                }
            }
        }
    }

    /// A vertical edge with perpendicular end ticks; the tick-to-tick distance
    /// is one card long edge at the current scale.
    private func referenceBar(height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3, height: height)
            VStack {
                endTick
                Spacer()
                endTick
            }
            .frame(height: height)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var endTick: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 90, height: 4)
    }
}
