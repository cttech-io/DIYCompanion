import SwiftUI
import UIKit

struct RulerView: View {
    @AppStorage("useMetric") private var isMetric: Bool = true
    @Environment(\.verticalSizeClass) private var vSize  // .compact = landscape

    // Physical points per inch for the current device.
    // Uses the formula: physicalPPI × boundsLongSide / nativeLongSide,
    // which correctly accounts for downsampled displays (e.g. iPhone 6+/7+/8+)
    // and is orientation-independent (nativeBounds.height is always portrait-natural).
    private static let pointsPerInch: CGFloat = {
        let native = UIScreen.main.nativeBounds.height  // always the long side
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

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .bottomTrailing) {
                    Color(.secondarySystemBackground)

                    if vSize == .compact {
                        // Landscape: ruler along the top edge (longest available side)
                        VStack(alignment: .leading, spacing: 0) {
                            RulerStrip(
                                length: geo.size.width,
                                pointsPerInch: Self.pointsPerInch,
                                isMetric: isMetric,
                                isHorizontal: true
                            )
                            Spacer()
                        }
                    } else {
                        // Portrait: ruler along the left edge (longest available side)
                        HStack(spacing: 0) {
                            RulerStrip(
                                length: geo.size.height,
                                pointsPerInch: Self.pointsPerInch,
                                isMetric: isMetric,
                                isHorizontal: false
                            )
                            VStack(alignment: .leading) {
                                Spacer()
                                instructionCard(horizontal: false)
                                    .padding(.bottom, 80)
                            }
                            .padding(.leading, 20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    unitPicker
                        .padding(.bottom, 20)
                        .padding(.trailing, 20)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Ruler")
            .navigationBarTitleDisplayMode(.automatic)
            .withSettingsToolbar()
        }
    }

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

    private func instructionCard(horizontal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: horizontal ? "arrow.up" : "arrow.left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(horizontal ? "Top edge is 0" : "Left edge is 0")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
            }
            Text(horizontal
                 ? "Place object flush against the top of the phone."
                 : "Place object flush against the left side of the phone.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 200)
    }
}

private struct RulerStrip: View {
    let length: CGFloat
    let pointsPerInch: CGFloat
    let isMetric: Bool
    let isHorizontal: Bool

    var body: some View {
        Canvas { ctx, size in
            // Measuring edge
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
