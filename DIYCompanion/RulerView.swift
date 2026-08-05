import SwiftUI
import UIKit

struct RulerView: View {
    @AppStorage(Prefs.useMetric) private var isMetric: Bool = true
    @AppStorage(Prefs.rulerCalibratedPPI) private var calibratedPPI: Double = 0
    @Environment(\.verticalSizeClass) private var vSize
    @State private var showSettings = false
    @State private var showCalibration = false
    @State private var markerA: CGFloat? = RulerView.simulatorSeed(0.26)
    @State private var markerB: CGFloat? = RulerView.simulatorSeed(0.63)
    @State private var activeMarker: MarkerID? = nil
    @State private var didCopy = false

    private enum MarkerID { case a, b }

    /// The scale used for all readouts and tick spacing. A user calibration
    /// (needed on iPad, where compatibility-mode scaling makes the physical
    /// density unknowable) overrides the per-model estimate when present.
    private var effectivePointsPerInch: CGFloat {
        calibratedPPI > 0 ? CGFloat(calibratedPPI) : Self.pointsPerInch
    }

    /// True when the hardware is an iPad — detected even while the iPhone-only
    /// app runs in iPhone-compatibility mode, where `userInterfaceIdiom` wrongly
    /// reports `.phone`. `uname` reads the real model; the Simulator exposes it
    /// through an environment variable instead.
    static let isRunningOnIPad: Bool = {
        if let simModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simModel.hasPrefix("iPad")
        }
        return currentModelIdentifier().hasPrefix("iPad")
    }()

    // Physical points per inch for the current device.
    // Uses the formula: physicalPPI × boundsLongSide / nativeLongSide,
    // which correctly accounts for downsampled displays (e.g. iPhone 6+/7+/8+)
    // and is orientation-independent (nativeBounds.height is always portrait-natural).
    private static let pointsPerInch: CGFloat = {
        let native = UIScreen.main.nativeBounds.height
        let boundsLong = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let physPPI = physicalPPI(
            model: currentModelIdentifier(),
            nativeLongSide: native,
            scale: UIScreen.main.scale
        )
        return physPPI * boundsLong / native
    }()

    /// Hardware model identifier (e.g. "iPhone14,5"). Unlike screen metrics,
    /// this can't be changed by Display Zoom, so it's the only robust key: a
    /// zoomed 6.1" phone and a real mini are indistinguishable by pixel counts.
    static func currentModelIdentifier() -> String {
        var sys = utsname()
        uname(&sys)
        return withUnsafeBytes(of: &sys.machine) { raw in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
    }

    /// Physical pixel density for a device. Keyed on the hardware model so
    /// Display Zoom can't miscalibrate the ruler; falls back to native pixel
    /// dimensions for unknown models (Simulator, future hardware).
    static func physicalPPI(model: String, nativeLongSide: CGFloat, scale: CGFloat) -> CGFloat {
        if let ppi = ppiByModel[model] { return ppi }
        return fallbackPPI(nativeLongSide: nativeLongSide, scale: scale)
    }

    private static func fallbackPPI(nativeLongSide: CGFloat, scale: CGFloat) -> CGFloat {
        switch Int(nativeLongSide) {
        case 1136: return 326  // iPhone SE 1st gen
        case 1334: return 326  // iPhone 8, SE 2nd/3rd gen
        case 1920: return 401  // iPhone 6+/7+/8+
        case 2436: return 458  // iPhone X, XS, 11 Pro
        case 2688: return 458  // iPhone XS Max, 11 Pro Max
        case 1792: return 326  // iPhone XR, 11
        case 2532: return 460  // iPhone 12/13-class
        case 2340: return 460  // ambiguous with a zoomed 6.1": assume full-size, not mini
        case 2778: return 458  // Plus / Pro Max class
        case 2556: return 460  // iPhone 14 Pro / 15-class
        case 2796: return 460  // Pro Max / Plus class
        case 2622: return 460  // iPhone 16 Pro
        case 2868: return 460  // iPhone 16 Pro Max
        default:   return scale >= 3 ? 460 : 326
        }
    }

    /// Model → physical ppi. Only the mini models (476) truly differ from the
    /// 460 default among recent devices, and they're exactly what Display Zoom
    /// makes ambiguous — so getting these two right is the whole point.
    static let ppiByModel: [String: CGFloat] = [
        // 12/13 mini — the ones a zoomed 6.1" phone masquerades as
        "iPhone13,1": 476,  // 12 mini
        "iPhone14,4": 476,  // 13 mini
        // 12/13/14/15/16 6.1" and Pro (460)
        "iPhone13,2": 460, "iPhone13,3": 460,          // 12, 12 Pro
        "iPhone14,5": 460, "iPhone14,2": 460,          // 13, 13 Pro
        "iPhone14,7": 460, "iPhone15,2": 460,          // 14, 14 Pro
        "iPhone15,4": 460, "iPhone16,1": 460,          // 15, 15 Pro
        "iPhone17,3": 460, "iPhone17,1": 460,          // 16, 16 Pro
        "iPhone17,5": 460,                              // 16e
        // Plus / Max (458–460)
        "iPhone13,4": 458,                              // 12 Pro Max
        "iPhone14,3": 458, "iPhone14,8": 458,          // 13 Pro Max, 14 Plus
        "iPhone15,3": 460, "iPhone15,5": 460,          // 14 Pro Max, 15 Plus
        "iPhone16,2": 460, "iPhone17,4": 460, "iPhone17,2": 460,  // 15 Pro Max, 16 Plus, 16 Pro Max
        // Older / SE
        "iPhone8,4": 326, "iPhone12,8": 326,           // SE 1st, SE 2nd
        "iPhone14,6": 326,                              // SE 3rd
        "iPhone12,1": 326, "iPhone11,8": 326,          // 11, XR
        "iPhone12,3": 458, "iPhone12,5": 458,          // 11 Pro, 11 Pro Max
    ]

    // MARK: - Measurement helpers

    static func readout(points: CGFloat, pointsPerInch: CGFloat, isMetric: Bool) -> String {
        let inches = points / pointsPerInch
        return isMetric
            ? String(format: "%.1f cm", inches * 2.54)
            : String(format: "%.2f\"", inches)
    }

    private func readout(_ pos: CGFloat) -> String {
        Self.readout(points: pos, pointsPerInch: effectivePointsPerInch, isMetric: isMetric)
    }

    private var spanText: String? {
        guard let a = markerA, let b = markerB else { return nil }
        return readout(abs(b - a))
    }

    private func resolveMarker(at pos: CGFloat) -> MarkerID {
        guard let a = markerA else { return .a }
        guard let b = markerB else { return .b }
        return abs(a - pos) <= abs(b - pos) ? .a : .b
    }

    private func placeMarker(_ id: MarkerID, at pos: CGFloat, limit: CGFloat) {
        let clamped = max(0, min(pos, limit))
        switch id {
        case .a: markerA = clamped
        case .b: markerB = clamped
        }
    }

    /// Simulator-only: open with two markers already placed so the ruler
    /// screenshots as a measurement in progress rather than a blank strip.
    /// No-op on device.
    /// Simulator-only: an initial marker position, as a fraction down the
    /// screen, so the ruler screenshots as a measurement in progress rather
    /// than a blank strip. Returns nil on device, where markers start empty.
    static func simulatorSeed(_ fraction: CGFloat) -> CGFloat? {
        #if targetEnvironment(simulator)
        return UIScreen.main.bounds.height * fraction
        #else
        return nil
        #endif
    }

    private func clearMarkers() {
        withAnimation(.easeInOut) {
            markerA = nil
            markerB = nil
        }
        activeMarker = nil
    }

    // MARK: - Accessibility

    private var mmInPoints: CGFloat { effectivePointsPerInch / 25.4 }

    private var accessibilityValueText: String {
        if let a = markerA, let b = markerB, let span = spanText {
            return "Marker A at \(readout(a)), marker B at \(readout(b)), distance \(span)"
        } else if let a = markerA {
            return "Marker A at \(readout(a))"
        } else {
            return "No markers placed"
        }
    }

    private func adjustActiveMarker(_ direction: AccessibilityAdjustmentDirection, limit: CGFloat) {
        // Move the active marker (defaulting to whichever is placed) by 1 mm.
        let id: MarkerID = activeMarker ?? (markerA != nil ? .a : .b)
        let current: CGFloat = (id == .a ? markerA : markerB) ?? 0
        let delta = direction == .increment ? mmInPoints : -mmInPoints
        placeMarker(id, at: current + delta, limit: limit)
        activeMarker = id
    }

    private func placeNextMarkerAccessibly(limit: CGFloat) {
        if markerA == nil {
            placeMarker(.a, at: limit / 2, limit: limit)
            activeMarker = .a
        } else if markerB == nil {
            placeMarker(.b, at: limit / 2, limit: limit)
            activeMarker = .b
        }
    }

    private func copyMeasurement() {
        let text: String
        if let s = spanText { text = s }
        else if let a = markerA { text = readout(a) }
        else { return }
        UIPasteboard.general.string = text
        withAnimation(.easeInOut) { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut) { didCopy = false }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color(.secondarySystemBackground).ignoresSafeArea()
                    if vSize == .compact {
                        landscapeLayout(geo: geo)
                    } else {
                        portraitLayout(geo: geo)
                    }
                }
            }
            .ignoresSafeArea(edges: vSize == .compact ? .top : [])
            .navigationTitle(vSize == .compact ? "" : "Ruler")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: vSize) { _, _ in
                // Markers are raw offsets along the active axis; on a portrait⇄
                // landscape flip that axis changes, so a stale offset would land
                // on the wrong (possibly off-screen) spot. Clear them.
                //
                // Not in the Simulator: this also fires as the size class
                // resolves during first layout, which would wipe the seeded
                // screenshot markers before anything is captured.
                #if !targetEnvironment(simulator)
                markerA = nil
                markerB = nil
                activeMarker = nil
                #endif
            }
            .toolbar(vSize == .compact ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showCalibration) {
            RulerCalibrationView(
                pointsPerInch: effectivePointsPerInch,
                onSave: { calibratedPPI = Double($0) },
                onReset: { calibratedPPI = 0 }
            )
        }
    }

    // MARK: - Calibration notice (iPad only)

    // Shown only on iPad, where iPhone-compatibility-mode scaling makes the
    // physical density unknowable until the user calibrates against a real card.
    @ViewBuilder
    private var calibrationNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: calibratedPPI > 0 ? "checkmark.circle.fill" : "ruler.fill")
                .foregroundStyle(calibratedPPI > 0 ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(calibratedPPI > 0 ? "Calibrated for this screen" : "Calibrate for accurate measurements")
                    .font(.footnote).bold()
                Text(calibratedPPI > 0
                     ? "iPad detected. Tap to recalibrate."
                     : "iPad detected — the ruler must be calibrated to measure accurately.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(calibratedPPI > 0 ? "Recalibrate" : "Calibrate")
                .font(.caption).bold()
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(calibratedPPI > 0 ? Color.secondary : Color.accentColor, in: Capsule())
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { showCalibration = true }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens ruler calibration")
    }

    // MARK: - Portrait layout

    private func portraitLayout(geo: GeometryProxy) -> some View {
        let rulerW: CGFloat = 68
        return ZStack(alignment: .bottomTrailing) {

            // Layer 1: ruler strip + gesture area
            HStack(spacing: 0) {
                RulerStrip(
                    length: geo.size.height,
                    pointsPerInch: effectivePointsPerInch,
                    isMetric: isMetric,
                    isHorizontal: false
                )
                Spacer()
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        let id = activeMarker ?? resolveMarker(at: v.startLocation.y)
                        activeMarker = id
                        placeMarker(id, at: v.location.y, limit: geo.size.height)
                    }
                    .onEnded { _ in activeMarker = nil }
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ruler measurement")
            .accessibilityValue(accessibilityValueText)
            .accessibilityHint("Swipe up or down to move the active marker by one millimetre. Use actions to place or clear markers.")
            .accessibilityAdjustableAction { adjustActiveMarker($0, limit: geo.size.height) }
            .accessibilityAction(named: "Place marker") { placeNextMarkerAccessibly(limit: geo.size.height) }
            .accessibilityAction(named: "Clear markers") { clearMarkers() }

            // Layer 2: marker lines
            if let a = markerA {
                hLine(y: a, color: Color.accentColor, width: geo.size.width)
                chip(readout(a),
                     at: CGPoint(x: rulerW + 56, y: max(16, min(a, geo.size.height - 16))),
                     color: Color.accentColor)
            }
            if let b = markerB {
                hLine(y: b, color: .orange, width: geo.size.width)
                chip(readout(b),
                     at: CGPoint(x: rulerW + 56, y: max(16, min(b, geo.size.height - 16))),
                     color: .orange)
            }

            // Layer 3: measurement card — rendered above lines so they don't overlap it
            VStack {
                Spacer()
                Group {
                    if markerA != nil || markerB != nil {
                        measurementCard
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        Text("Tap to place a marker")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut, value: markerA == nil && markerB == nil)
                .padding(.bottom, 90)
            }
            .padding(.leading, rulerW + 16)
            .padding(.trailing, 16)

            // Layer 4: unit picker
            unitPicker
                .padding(.bottom, 20)
                .padding(.trailing, 20)

            // Layer 5: iPad calibration notice, kept clear of the ruler strip
            if Self.isRunningOnIPad {
                VStack {
                    calibrationNotice
                        .padding(.top, 8)
                    Spacer()
                }
                .padding(.leading, rulerW + 8)
                .padding(.trailing, 12)
            }
        }
    }

    // MARK: - Landscape layout

    private func landscapeLayout(geo: GeometryProxy) -> some View {
        let rulerH: CGFloat = 68
        return ZStack {
            // Layer 1: ruler strip + gesture area
            VStack(alignment: .leading, spacing: 0) {
                RulerStrip(
                    length: geo.size.width,
                    pointsPerInch: effectivePointsPerInch,
                    isMetric: isMetric,
                    isHorizontal: true
                )
                Spacer()
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        let id = activeMarker ?? resolveMarker(at: v.startLocation.x)
                        activeMarker = id
                        placeMarker(id, at: v.location.x, limit: geo.size.width)
                    }
                    .onEnded { _ in activeMarker = nil }
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ruler measurement")
            .accessibilityValue(accessibilityValueText)
            .accessibilityHint("Swipe up or down to move the active marker by one millimetre. Use actions to place or clear markers.")
            .accessibilityAdjustableAction { adjustActiveMarker($0, limit: geo.size.width) }
            .accessibilityAction(named: "Place marker") { placeNextMarkerAccessibly(limit: geo.size.width) }
            .accessibilityAction(named: "Clear markers") { clearMarkers() }

            let lineHeight = geo.size.height - geo.safeAreaInsets.bottom
            if let a = markerA {
                vLine(x: a, color: Color.accentColor, height: lineHeight)
                chip(readout(a),
                     at: CGPoint(x: max(32, min(a, geo.size.width - 32)), y: rulerH - 4),
                     color: Color.accentColor)
            }
            if let b = markerB {
                vLine(x: b, color: .orange, height: lineHeight)
                chip(readout(b),
                     at: CGPoint(x: max(32, min(b, geo.size.width - 32)), y: rulerH - 4),
                     color: .orange)
            }

            // Layer 3: measurement card — rendered above lines
            VStack(alignment: .leading) {
                Group {
                    if markerA != nil || markerB != nil {
                        measurementCard
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        Text("Tap to place a marker")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut, value: markerA == nil && markerB == nil)
                .padding(.leading, 20)
                .padding(.top, rulerH + 16)
                Spacer()
            }

            // Layer 4: floating controls
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Spacer()
                    unitPicker
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .padding(10)
                            .background(Color(.tertiarySystemBackground), in: Circle())
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            // Layer 5: iPad calibration notice, kept clear of the ruler strip
            if Self.isRunningOnIPad {
                VStack {
                    HStack {
                        calibrationNotice
                            .frame(maxWidth: 460)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.top, rulerH + 12)
            }
        }
    }

    // MARK: - Marker overlays

    private func hLine(y: CGFloat, color: Color, width: CGFloat) -> some View {
        color.opacity(0.75)
            .frame(width: width, height: 2)
            .position(x: width / 2, y: y)
            .allowsHitTesting(false)
    }

    private func vLine(x: CGFloat, color: Color, height: CGFloat) -> some View {
        color.opacity(0.75)
            .frame(width: 2, height: height)
            .position(x: x, y: height / 2)
            .allowsHitTesting(false)
    }

    private func chip(_ text: String, at point: CGPoint, color: Color) -> some View {
        Text(text)
            .font(.caption2).bold().monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
            .position(point)
            .allowsHitTesting(false)
    }

    // MARK: - Measurement card

    private var measurementCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let a = markerA {
                HStack(spacing: 6) {
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                    Text(readout(a))
                        .font(.system(.callout, design: .rounded)).bold().monospacedDigit()
                }
            }
            if let b = markerB {
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text(readout(b))
                        .font(.system(.callout, design: .rounded)).bold().monospacedDigit()
                }
            }
            if let span = spanText {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: vSize == .compact ? "arrow.left.and.right" : "arrow.up.and.down")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(span)
                        .font(.system(.callout, design: .rounded)).bold().monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                }
            }
            Divider()
            HStack {
                Button { copyMeasurement() } label: {
                    Label(
                        didCopy ? "Copied" : "Copy",
                        systemImage: didCopy ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption).bold()
                }
                .tint(didCopy ? .green : .accentColor)
                .animation(.easeInOut, value: didCopy)
                Spacer()
                Button {
                    clearMarkers()
                } label: {
                    Text("Clear").font(.caption).bold()
                }
                .tint(.red)
            }
        }
        .padding(14)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 180)
    }

    // MARK: - Unit picker

    private var unitPicker: some View {
        Picker("Unit", selection: $isMetric) {
            Text("cm").tag(true)
            Text("in").tag(false)
        }
        .pickerStyle(.segmented)
        .frame(width: 140)
        .padding(8)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct RulerStrip: View {
    let length: CGFloat
    let pointsPerInch: CGFloat
    let isMetric: Bool
    let isHorizontal: Bool

    var body: some View {
        Canvas { ctx, size in
            var edge = Path()
            if isHorizontal {
                edge.move(to: .init(x: 0, y: 1))
                edge.addLine(to: .init(x: size.width, y: 1))
            } else {
                edge.move(to: .init(x: 1, y: 0))
                edge.addLine(to: .init(x: 1, y: size.height))
            }
            ctx.stroke(edge, with: .color(.primary), lineWidth: 2)

            if isMetric {
                drawMetric(ctx: ctx, size: size)
            } else {
                drawImperial(ctx: ctx, size: size)
            }
        }
        .frame(
            width:  isHorizontal ? length : 68,
            height: isHorizontal ? 68    : length
        )
        .background(Color(.tertiarySystemBackground))
        .accessibilityLabel("Ruler")
        .accessibilityHint(isHorizontal
            ? "Place object flush against the top of the phone to measure"
            : "Place object flush against the left side of the phone to measure")
    }

    private func drawMetric(ctx: GraphicsContext, size: CGSize) {
        let ppmm  = pointsPerInch / 25.4
        let limit = isHorizontal ? size.width : size.height
        let total = Int(limit / ppmm) + 1
        for mm in 0..<total {
            let pos    = CGFloat(mm) * ppmm
            let isCm   = mm % 10 == 0
            let isMid  = mm % 5  == 0
            let length: CGFloat = isCm ? 38 : isMid ? 24 : 14
            tick(ctx: ctx, pos: pos, length: length)
            if isCm && mm > 0 {
                label(ctx: ctx, text: "\(mm / 10)", pos: pos, tickLength: length)
            }
        }
    }

    private func drawImperial(ctx: GraphicsContext, size: CGSize) {
        let pp16  = pointsPerInch / 16.0
        let limit = isHorizontal ? size.width : size.height
        let total = Int(limit / pp16) + 1
        for i in 0..<total {
            let pos      = CGFloat(i) * pp16
            let isIn     = i % 16 == 0
            let isHalf   = i % 8  == 0
            let isQtr    = i % 4  == 0
            let isEighth = i % 2  == 0
            let length: CGFloat = isIn ? 38 : isHalf ? 28 : isQtr ? 20 : isEighth ? 13 : 9
            tick(ctx: ctx, pos: pos, length: length)
            if isIn && i > 0 {
                label(ctx: ctx, text: "\(i / 16)\"", pos: pos, tickLength: length)
            }
        }
    }

    private func tick(ctx: GraphicsContext, pos: CGFloat, length: CGFloat) {
        var path = Path()
        if isHorizontal {
            path.move(to: .init(x: pos, y: 2))
            path.addLine(to: .init(x: pos, y: 2 + length))
        } else {
            path.move(to: .init(x: 2, y: pos))
            path.addLine(to: .init(x: 2 + length, y: pos))
        }
        ctx.stroke(path, with: .color(.primary.opacity(0.8)), lineWidth: 1.5)
    }

    private func label(ctx: GraphicsContext, text: String, pos: CGFloat, tickLength: CGFloat) {
        let resolved = ctx.resolve(
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded))
        )
        if isHorizontal {
            ctx.draw(resolved, at: .init(x: pos, y: tickLength + 6), anchor: .top)
        } else {
            ctx.draw(resolved, at: .init(x: tickLength + 5, y: pos), anchor: .leading)
        }
    }
}
