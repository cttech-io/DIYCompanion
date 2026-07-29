import XCTest
import CoreGraphics
import UIKit
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
}
