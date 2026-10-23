import XCTest
import CoreGraphics
import UIKit
import SwiftUI
@testable import DIYCompanion

// Pure-logic tests for the classification/formatting helpers extracted from the
// hardware-coupled managers. These need no device or mocking.
//
// NOTE: attach this file to a "Unit Testing Bundle" target in Xcode
// (File ▸ New ▸ Target ▸ Unit Testing Bundle, host app = DIYCompanion).
final class DIYCompanionLogicTests: XCTestCase {

    // MARK: - Ruler PPI (finding #3)

    func testPPILookup_zoomedIPhone12_notMistakenForMini() {
        // A Display-Zoomed iPhone 12/13/14 reports nativeBounds.height == 2340,
        // identical to a real 12/13 mini. Keyed on the model, the full-size phone
        // must resolve to 460 ppi, never the mini's 476.
        let full = RulerView.physicalPPI(model: "iPhone13,2", nativeLongSide: 2340, scale: 3)
        XCTAssertEqual(full, 460, accuracy: 0.001)

        let mini = RulerView.physicalPPI(model: "iPhone13,1", nativeLongSide: 2340, scale: 3)
        XCTAssertEqual(mini, 476, accuracy: 0.001)
    }

    func testPPILookup_tableIsInternallyConsistent() {
        XCTAssertEqual(RulerView.physicalPPI(model: "iPhone14,4", nativeLongSide: 2340, scale: 3), 476, accuracy: 0.001) // 13 mini
        XCTAssertEqual(RulerView.physicalPPI(model: "iPhone17,1", nativeLongSide: 2622, scale: 3), 460, accuracy: 0.001) // 16 Pro
        XCTAssertEqual(RulerView.physicalPPI(model: "iPhone12,8", nativeLongSide: 1334, scale: 2), 326, accuracy: 0.001) // SE 2nd
    }

    func testPPILookup_unknownModel_fallsBackToNativeBounds() {
        // Simulator / future hardware: fall back to the native-pixel heuristic.
        XCTAssertEqual(RulerView.physicalPPI(model: "x86_64", nativeLongSide: 2532, scale: 3), 460, accuracy: 0.001)
        XCTAssertEqual(RulerView.physicalPPI(model: "arm64", nativeLongSide: 1334, scale: 2), 326, accuracy: 0.001)
    }

    // MARK: - Ruler formatting

    func testRulerReadout_metricAndImperialFormatting() {
        let ppi: CGFloat = 460
        // 1 inch worth of points at 460 ppi
        XCTAssertEqual(RulerView.readout(points: ppi, pointsPerInch: ppi, isMetric: true), "2.5 cm")
        XCTAssertEqual(RulerView.readout(points: ppi, pointsPerInch: ppi, isMetric: false), "1.00\"")
        XCTAssertEqual(RulerView.readout(points: 0, pointsPerInch: ppi, isMetric: true), "0.0 cm")
    }

    // MARK: - Ruler calibration clamp (issue #1)

    func testClampedPPI_rawAboveCeiling_returnsCeiling() {
        // The bug: the bar and slider clamped, but Save persisted the raw value,
        // so a scale the layout could never display got written to prefs.
        let middle: CGFloat = 400
        let ceiling = RulerCalibrationView.maxPPI(middleHeight: middle)
        XCTAssertEqual(
            RulerCalibrationView.clampedPPI(ceiling + 250, middleHeight: middle),
            ceiling, accuracy: 0.001
        )
    }

    func testClampedPPI_rawBelowFloor_returnsFloor() {
        XCTAssertEqual(
            RulerCalibrationView.clampedPPI(5, middleHeight: 600),
            RulerCalibrationView.minPPI, accuracy: 0.001
        )
    }

    func testClampedPPI_inRangeValueUnchanged() {
        XCTAssertEqual(
            RulerCalibrationView.clampedPPI(120, middleHeight: 600),
            120, accuracy: 0.001
        )
    }

    func testClampedPPI_degenerateHeight_staysAtOrAboveFloor() {
        // A zero/for-tiny region makes the ceiling collapse below the floor;
        // the clamp must not invert and return something nonsensical.
        XCTAssertGreaterThanOrEqual(
            RulerCalibrationView.clampedPPI(300, middleHeight: 0),
            RulerCalibrationView.minPPI
        )
    }

    // MARK: - Noise tiers (part 2)

    func testNoiseTier_boundaries() {
        XCTAssertEqual(NoiseManager.tier(forDBFS: -80), .quiet)
        XCTAssertEqual(NoiseManager.tier(forDBFS: -70), .moderate)   // -70 is not < -70
        XCTAssertEqual(NoiseManager.tier(forDBFS: -60), .moderate)
        XCTAssertEqual(NoiseManager.tier(forDBFS: -50), .loud)
        XCTAssertEqual(NoiseManager.tier(forDBFS: -40), .loud)
        XCTAssertEqual(NoiseManager.tier(forDBFS: -30), .dangerous)
        XCTAssertEqual(NoiseManager.tier(forDBFS: 0), .dangerous)
    }

    // MARK: - Magnetometer classification (part 2)

    func testThreatClassification_sensitivityScaling() {
        // Default sensitivity: caution at 25 µT, danger at 60 µT.
        XCTAssertEqual(MagnetometerManager.classify(deviation: 10, sensitivity: 1.0), .safe)
        XCTAssertEqual(MagnetometerManager.classify(deviation: 30, sensitivity: 1.0), .caution)
        XCTAssertEqual(MagnetometerManager.classify(deviation: 70, sensitivity: 1.0), .danger)

        // 2× sensitivity halves the thresholds (caution 12.5, danger 30).
        XCTAssertEqual(MagnetometerManager.classify(deviation: 15, sensitivity: 2.0), .caution)
        XCTAssertEqual(MagnetometerManager.classify(deviation: 35, sensitivity: 2.0), .danger)

        // 0.5× sensitivity doubles them (caution 50, danger 120).
        XCTAssertEqual(MagnetometerManager.classify(deviation: 30, sensitivity: 0.5), .safe)
        XCTAssertEqual(MagnetometerManager.classify(deviation: 55, sensitivity: 0.5), .caution)
    }

    func testThreatSeverityOrdering_drivesEscalationHaptic() {
        // The scanner haptic fires only on escalation, decided by Comparable
        // ordering — which is derived from declaration order, so lock it in.
        XCTAssertLessThan(MagnetometerManager.Threat.safe, .caution)
        XCTAssertLessThan(MagnetometerManager.Threat.caution, .danger)
    }

    // MARK: - Flashlight naming (part 2)

    func testFlashlightName_britishVariants() {
        XCTAssertEqual(resolveFlashlightName(for: ["en-GB"]), "Torch")
        XCTAssertEqual(resolveFlashlightName(for: ["en-AU"]), "Torch")
        XCTAssertEqual(resolveFlashlightName(for: ["en-US"]), "Flashlight")
        XCTAssertEqual(resolveFlashlightName(for: ["en"]), "Flashlight")
        XCTAssertEqual(resolveFlashlightName(for: ["fr-FR"]), "Flashlight")
        XCTAssertEqual(resolveFlashlightName(for: []), "Flashlight")
    }

    // MARK: - Plumb angle (finding #7)

    func testPlumbAngle_fromGravityVector() {
        // Portrait, perfectly plumb: gravity straight down the screen (0, -1).
        XCTAssertEqual(
            LevelManager.plumbAngleDegrees(gx: 0, gy: -1, orientation: .portrait),
            0, accuracy: 0.001
        )
        // Top leaning 30° to the right.
        XCTAssertEqual(
            LevelManager.plumbAngleDegrees(gx: 0.5, gy: -sqrt(3) / 2, orientation: .portrait),
            30, accuracy: 0.01
        )
        // Symmetric lean to the left is negative.
        XCTAssertEqual(
            LevelManager.plumbAngleDegrees(gx: -0.5, gy: -sqrt(3) / 2, orientation: .portrait),
            -30, accuracy: 0.01
        )
        // Upside-down portrait, plumb: gravity now points toward +y.
        XCTAssertEqual(
            LevelManager.plumbAngleDegrees(gx: 0, gy: 1, orientation: .portraitUpsideDown),
            0, accuracy: 0.001
        )
        // Landscape, held plumb: gravity lies along the long axis (gx ≈ ±1) with
        // gy ≈ 0. Both landscape orientations must read ~0, not pinned near ±180.
        XCTAssertEqual(
            LevelManager.plumbAngleDegrees(gx: -1, gy: 0, orientation: .landscapeLeft),
            0, accuracy: 0.001
        )
        XCTAssertEqual(
            LevelManager.plumbAngleDegrees(gx: 1, gy: 0, orientation: .landscapeRight),
            0, accuracy: 0.001
        )
        // landscapeLeft leaning 30°: gravity (−0.866, −0.5) → +30°.
        XCTAssertEqual(
            LevelManager.plumbAngleDegrees(gx: -sqrt(3) / 2, gy: -0.5, orientation: .landscapeLeft),
            30, accuracy: 0.01
        )
    }

    // MARK: - Level hysteresis (1.0.2)

    func testLevelState_hysteresisHoldsThroughNoiseNearThreshold() {
        // Entering needs < 0.5°; once level, only > 0.8° drops it.
        XCTAssertFalse(LevelManager.levelState(wasLevel: false, deviation: 0.6))
        XCTAssertTrue(LevelManager.levelState(wasLevel: false, deviation: 0.4))
        XCTAssertTrue(LevelManager.levelState(wasLevel: true, deviation: 0.6))
        XCTAssertFalse(LevelManager.levelState(wasLevel: true, deviation: 0.9))

        // A noisy reading wobbling around 0.5° must not toggle the state
        // (which flickered the ring and re-fired the haptic every crossing).
        var level = false
        var transitions = 0
        for deviation in [0.45, 0.55, 0.48, 0.62, 0.51, 0.70, 0.49, 0.58] {
            let next = LevelManager.levelState(wasLevel: level, deviation: deviation)
            if next != level { transitions += 1 }
            level = next
        }
        XCTAssertEqual(transitions, 1)
    }

    // MARK: - Degree formatting (1.0.2)

    func testFormatDegrees_normalisesNegativeZero() {
        XCTAssertEqual(formatDegrees(-0.04), "0.0°")
        XCTAssertEqual(formatDegrees(0.04), "0.0°")
        XCTAssertEqual(formatDegrees(-0.05), "-0.1°")
        XCTAssertEqual(formatDegrees(12.345), "12.3°")
    }

    // MARK: - Review prompt gate (1.0.2)

    func testReviewGate_promptsOnlyAtMilestones() {
        XCTAssertFalse(ReviewGate.shouldPrompt(successes: 2, promptsShown: 0))
        XCTAssertTrue(ReviewGate.shouldPrompt(successes: 3, promptsShown: 0))
        XCTAssertFalse(ReviewGate.shouldPrompt(successes: 10, promptsShown: 1))
        XCTAssertTrue(ReviewGate.shouldPrompt(successes: 15, promptsShown: 1))
        XCTAssertFalse(ReviewGate.shouldPrompt(successes: 500, promptsShown: 2))
    }

    func testReviewGate_asksOnlyAfterAPendingSuccess() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        _ = ReviewGate.takePromptDecision(defaults: defaults)   // clear any pending state
        ReviewGate.recordSuccess(defaults: defaults)
        ReviewGate.recordSuccess(defaults: defaults)
        XCTAssertFalse(ReviewGate.takePromptDecision(defaults: defaults))   // only 2
        ReviewGate.recordSuccess(defaults: defaults)
        XCTAssertTrue(ReviewGate.takePromptDecision(defaults: defaults))    // 3rd, at a tab switch
        XCTAssertFalse(ReviewGate.takePromptDecision(defaults: defaults))   // consumed
    }

    // MARK: - Status colour contrast (1.0.2)

    func testStatusTextColours_meetTextContrastOnTheirLightModeChips() {
        func luminance(_ c: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        func blend(_ fg: UIColor, over bg: UIColor, alpha: CGFloat) -> UIColor {
            var fr: CGFloat = 0, fgG: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
            var br: CGFloat = 0, bgG: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            fg.getRed(&fr, green: &fgG, blue: &fb, alpha: &fa)
            bg.getRed(&br, green: &bgG, blue: &bb, alpha: &ba)
            return UIColor(red: fr * alpha + br * (1 - alpha), green: fgG * alpha + bgG * (1 - alpha),
                           blue: fb * alpha + bb * (1 - alpha), alpha: 1)
        }
        let light = UITraitCollection(userInterfaceStyle: .light)
        let page = UIColor.secondarySystemBackground.resolvedColor(with: light)
        let pairs: [(Color, UIColor)] = [
            (.statusGreenText, .systemGreen), (.statusOrangeText, .systemOrange),
            (.statusRedText, .systemRed), (.statusYellowText, .systemYellow),
        ]
        for (text, tint) in pairs {
            let fg = UIColor(text).resolvedColor(with: light)
            let chip = blend(tint.resolvedColor(with: light), over: page, alpha: 0.18)
            let (l1, l2) = (luminance(fg), luminance(chip))
            let ratio = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(tint) chip text is \(ratio):1")
        }

        // Accent text on both light-mode page backgrounds it appears on.
        let accent = UIColor(Color.accentText).resolvedColor(with: light)
        for bg in [UIColor.secondarySystemBackground, .tertiarySystemBackground, .systemBackground] {
            let (l1, l2) = (luminance(accent), luminance(bg.resolvedColor(with: light)))
            let ratio = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "accent text on \(bg) is \(ratio):1")
        }
    }
}
