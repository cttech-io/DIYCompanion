import SwiftUI
import UIKit

/// Reference-counted owner of `isIdleTimerDisabled` so that several tools can
/// each request "keep awake" without one tab's teardown clobbering another's
/// request when tab switches interleave onAppear/onDisappear.
private enum ScreenAwake {
    private static var count = 0

    static func acquire() {
        count += 1
        apply()
    }

    static func release() {
        count = max(0, count - 1)
        apply()
    }

    private static func apply() {
        UIApplication.shared.isIdleTimerDisabled = count > 0
    }
}

private struct KeepScreenAwakeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { ScreenAwake.acquire() }
            .onDisappear { ScreenAwake.release() }
    }
}

extension View {
    /// Prevents the screen dimming/locking while this view is on screen — e.g.
    /// holding a level against a shelf for a minute mid-measurement. The idle
    /// timer has no effect while backgrounded, so no scene-phase handling is
    /// needed; the flag simply persists correctly across foreground returns.
    func keepsScreenAwake() -> some View {
        modifier(KeepScreenAwakeModifier())
    }
}

// MARK: - Legible status colours

extension Color {
    /// Text colour for a status chip (coloured text on an 18% tint of the same
    /// colour). The bright system tints work in dark mode but fall well under
    /// the 4.5:1 text minimum in light mode — systemYellow on a yellow chip is
    /// 1.3:1 — so light mode gets a darkened shade measured to clear 4.5:1.
    static func statusText(_ dark: UIColor, light: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : UIColor(rgb: light)
        })
    }

    static let statusGreenText  = statusText(.systemGreen,  light: 0x1E7334)
    static let statusOrangeText = statusText(.systemOrange, light: 0x945600)
    static let statusRedText    = statusText(.systemRed,    light: 0xB22922)
    static let statusYellowText = statusText(.systemYellow, light: 0x806600)

    /// Label colour on a solid accent fill. The amber accent is light in both
    /// appearances, so white on it is ~2:1; black is 10.6:1.
    static let onAccent = Color.black
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
