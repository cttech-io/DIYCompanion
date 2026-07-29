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
