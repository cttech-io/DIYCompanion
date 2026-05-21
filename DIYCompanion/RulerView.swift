import SwiftUI
import UIKit

struct RulerView: View {
    @AppStorage("useMetric") private var isMetric: Bool = true
    @Environment(\.verticalSizeClass) private var vSize
    @State private var showSettings = false
    @State private var markerA: CGFloat? = nil
    @State private var markerB: CGFloat? = nil
    @State private var activeMarker: MarkerID? = nil
    @State private var didCopy = false

    private enum MarkerID { case a, b }

    // Physical points per inch for the current device.
    // Uses the formula: physicalPPI × boundsLongSide / nativeLongSide,
    // which correctly accounts for downsampled displays (e.g. iPhone 6+/7+/8+)
    // and is orientation-independent (nativeBounds.height is always portrait-natural).
    private static let pointsPerInch: CGFloat = {
        let native = UIScreen.main.nativeBounds.height
        let boundsLong = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let physPPI: CGFloat
        switch Int(native) {
        case 1136: physPPI = 326  // iPhone SE 1st gen
        case 1334: physPPI = 326  // iPhone 8, SE 2nd/3rd gen
        case 1920: physPPI = 401  // iPhone 6+/7+/8+
        case 2436: physPPI = 458  // iPhone X, XS, 11 Pro
        case 2688: physPPI = 458  // iPhone XS Max, 11 Pro Max
        case 1792: physPPI = 326  // iPhone XR, 11
        case 2532: physPPI = 460  // iPhone 12, 13, 14, 15, 16
        case 2340: physPPI = 476  // iPhone 12 mini, 13 mini
        case 2778: physPPI = 458  // iPhone 12/13/14/15/16 Plus/Pro Max variants
        case 2556: physPPI = 460  // iPhone 14 Pro, 15, 15 Pro, 16
        case 2796: physPPI = 460  // iPhone 14/15 Pro Max, 15/16 Plus
        case 2622: physPPI = 460  // iPhone 16 Pro
        case 2868: physPPI = 460  // iPhone 16 Pro Max
        default:   physPPI = UIScreen.main.scale >= 3 ? 460 : 326
        }
        return physPPI * boundsLong / native
    }()

    // MARK: - Measurement helpers

    private func readout(_ pos: CGFloat) -> String {
        let inches = pos / Self.pointsPerInch
        return isMetric
            ? String(format: "%.1f cm", inches * 2.54)
            : String(format: "%.2f\"", inches)
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
            .navigationBarTitleDisplayMode(.automatic)
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
    }

    // MARK: - Portrait layout

    private func portraitLayout(geo: GeometryProxy) -> some View {
        let rulerW: CGFloat = 68
        return ZStack(alignment: .bottomTrailing) {
            // Layer 1: ruler strip + gesture area
            HStack(spacing: 0) {
                RulerStrip(
                    length: geo.size.height,
                    pointsPerInch: Self.pointsPerInch,
                    isMetric: isMetric,
                    isHorizontal: false
                )
                Spacer()
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        if activeMarker == nil {
                            activeMarker = resolveMarker(at: v.startLocation.y)
                        }
                        placeMarker(activeMarker!, at: v.location.y, limit: geo.size.height)
                    }
                    .onEnded { _ in activeMarker = nil }
            )

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
                    pointsPerInch: Self.pointsPerInch,
                    isMetric: isMetric,
                    isHorizontal: true
                )
                Spacer()
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        if activeMarker == nil {
                            activeMarker = resolveMarker(at: v.startLocation.x)
                        }
                        placeMarker(activeMarker!, at: v.location.x, limit: geo.size.width)
                    }
                    .onEnded { _ in activeMarker = nil }
            )

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
                    Image(systemName: "arrow.up.and.down")
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
                    withAnimation(.easeInOut) {
                        markerA = nil
                        markerB = nil
                    }
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
