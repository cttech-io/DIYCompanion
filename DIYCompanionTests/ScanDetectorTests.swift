import XCTest
import simd
@testable import DIYCompanion

// Scanner 2.0 detector, exercised against a physics model of a phone sliding
// along a wall over a steel fixing. The model fixes the *shape* of the problem
// (dipole fall-off, Earth's field, rotation, drift, bias updates); the absolute
// signal and noise levels are estimates until replaced by recorded sweeps.

/// Phone sweeping horizontally along a wall, screen facing the room, over a
/// fixing buried at the origin. World frame: x east, y north, z up; lengths in mm.
struct SweepSimulator {
    /// UK field: 49 µT at 66° inclination, pointing north and down.
    var earth = SIMD3<Double>(0, 19.9, -44.8)
    /// Compass bearing the wall faces (direction of its outward normal), degrees.
    var wallFacing = 0.0
    /// Sensor to fixing, through the wall surface: 12.5 mm board + ~4.5 mm into the phone.
    var depth = 17.0
    /// Effective volume × demagnetisation for induced magnetisation (mm³);
    /// ~6 µT peak at 17 mm for a drywall screw on a north-facing wall, as in
    /// the accuracy note's model. Zero = no ferrous metal.
    var inducedVolume = 490.0
    /// Remanent moment along the screw's axis (µT·mm³), e.g. from a magnetic driver bit.
    var remanence = 0.0
    var noise = 0.4                 // µT per axis, white
    var gyroBias = 0.0005           // rad/s residual after iOS correction
    var wobbleDegrees = 0.0         // hand roll about the screen normal
    var wobblePeriod = 2.5
    var drift = SIMD3<Double>.zero  // µT per second, device frame
    /// iOS's compass calibration wandering off: from `time`, the calibrated
    /// field (only) ramps by `step` per second, as seen near metal on a real phone.
    var iosDrift: (time: Double, step: SIMD3<Double>)?
    /// Added to the field throughout, e.g. a MagSafe magnet (µT, device frame).
    var accessoryField = SIMD3<Double>.zero
    var hardIron = SIMD3<Double>(-120, 45, 310)
    var rate = 100.0
    var seed: UInt64 = 1

    var wallNormal: SIMD3<Double> {
        let a = wallFacing * .pi / 180
        return SIMD3(sin(a), cos(a), 0)
    }

    /// Field from the fixing at displacement `r` (mm) from it.
    func fixingField(at r: SIMD3<Double>) -> SIMD3<Double> {
        let m = earth * inducedVolume + (-wallNormal) * remanence
        let d = simd_length(r)
        guard d > 0, simd_length(m) > 0 else { return .zero }
        let u = r / d
        return (3 * simd_dot(m, u) * u - m) / (d * d * d)
    }

    /// One position per sample along the wall, mm along its horizontal tangent.
    /// Starts with `still` seconds parked at the first position (calibration).
    func run(path: [Double], still: Double = 1.0) -> [ScanSample] {
        var rng = SplitMix(seed: seed)
        let up = SIMD3<Double>(0, 0, 1)
        let n = wallNormal
        let tangent = simd_cross(up, n)
        // Device x = tangent, y = up, z = out of the screen (= wall normal).
        let mount = simd_quatd(simd_double3x3(columns: (tangent, up, n)))
        let dt = 1 / rate
        let positions = Array(repeating: path.first ?? 0, count: Int(still * rate)) + path

        var samples: [ScanSample] = []
        var lastRoll = 0.0
        for (i, x) in positions.enumerated() {
            let t = Double(i) * dt
            let w = 2 * Double.pi / wobblePeriod
            let roll = wobbleDegrees * .pi / 180 * sin(w * t)
            let rollRate = i == 0 ? 0 : (roll - lastRoll) / dt
            lastRoll = roll
            let attitude = mount * simd_quatd(angle: roll, axis: SIMD3(0, 0, 1))

            let sensor = tangent * x + n * depth
            let world = earth + fixingField(at: sensor)
            let device = attitude.inverse.act(world) + accessoryField + drift * t
            let jitter = SIMD3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * noise
            var calibrated = device + jitter
            if let d = iosDrift, t >= d.time { calibrated += d.step * (t - d.time) }
            let raw = device + jitter + hardIron
            let gyroNoise = SIMD3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * 0.002
            samples.append(ScanSample(
                time: t, field: calibrated, rawField: raw,
                rotationRate: SIMD3(0, 0, rollRate) + gyroNoise + gyroBias,
                accuracy: 2))
        }
        return samples
    }

    /// Steady sweep from `from` to `to` mm at `speed` mm/s.
    func sweep(from: Double = -150, to: Double = 150, speed: Double = 30) -> [ScanSample] {
        let count = Int(abs(to - from) / speed * rate)
        return run(path: (0..<count).map { from + (to - from) * Double($0) / Double(count) })
    }

    /// Strongest field change the fixing can produce along the sweep line.
    func truePeak(from: Double = -150, to: Double = 150) -> Double {
        let tangent = simd_cross(SIMD3(0, 0, 1), wallNormal)
        return stride(from: from, through: to, by: 0.5)
            .map { simd_length(fixingField(at: tangent * $0 + wallNormal * depth)) }
            .max() ?? 0
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func gaussian() -> Double {
        let u = max(uniform(), .leastNonzeroMagnitude)
        return sqrt(-2 * log(u)) * cos(2 * .pi * uniform())
    }
}

final class ScanDetectorTests: XCTestCase {

    private func replay(_ samples: [ScanSample], detector: ScanDetector = ScanDetector()) -> [ScanDetector.Reading] {
        var d = detector
        return samples.map { d.process($0) }
    }

    /// Sweep position (mm) of each reading, aligned with `SweepSimulator.sweep`.
    private func positions(_ sim: SweepSimulator, from: Double = -150, to: Double = 150, speed: Double = 30) -> [Double] {
        let count = Int(abs(to - from) / speed * sim.rate)
        let still = Array(repeating: from, count: Int(sim.rate))
        return still + (0..<count).map { from + (to - from) * Double($0) / Double(count) }
    }

    private let facings = [0.0, 45, 90, 135, 180, 225, 270, 315]

    // MARK: - Must not detect

    func testBlankWall_noFalseTriggers_withNoiseWobbleAndDrift() {
        for facing in facings {
            for seed in UInt64(1)...5 {
                var sim = SweepSimulator()
                sim.wallFacing = facing
                sim.inducedVolume = 0
                sim.wobbleDegrees = 10
                sim.drift = SIMD3(0.03, -0.02, 0.04)
                sim.seed = seed
                let readings = replay(sim.sweep())
                let worst = readings.map(\.deviation).max() ?? 0
                XCTAssertFalse(readings.contains { $0.level > .none },
                               "false trigger facing \(facing)°, seed \(seed), worst \(worst) µT")
            }
        }
    }

    func testRotation_isCompensatedByGyro() {
        var sim = SweepSimulator()
        sim.inducedVolume = 0
        sim.noise = 0
        sim.wobbleDegrees = 40
        let readings = replay(sim.run(path: Array(repeating: 0, count: 500)))
        let worst = readings.map(\.deviation).max() ?? 0
        XCTAssertLessThan(worst, 1.0, "rotation leaked into the reading")

        // Without compensation the same rotation would swing the vector by ~25 µT.
        let roll = 40 * Double.pi / 180
        let swing = simd_length(simd_quatd(angle: roll, axis: SIMD3(0, 0, 1)).act(sim.earth) - sim.earth)
        XCTAssertGreaterThan(swing, 10)
    }

    func testSlowDrift_whileStill_doesNotTrigger() {
        var sim = SweepSimulator()
        sim.inducedVolume = 0
        sim.drift = SIMD3(0.05, 0.05, -0.05)   // ~10 µT over two minutes
        let readings = replay(sim.run(path: Array(repeating: 0, count: 12_000)))
        XCTAssertFalse(readings.contains { $0.level > .none })
    }

    func testIOSCalibrationWandering_isIgnored() {
        var sim = SweepSimulator()
        sim.inducedVolume = 0
        sim.iosDrift = (time: 4, step: SIMD3(6, -4, 3))
        var detector = ScanDetector()
        let readings = sim.sweep().map { detector.process($0) }
        XCTAssertFalse(readings.contains { $0.level > .none })
        XCTAssertGreaterThan(detector.iosDrift, 20)

        // Without the raw sensor it falls back to iOS's field and is fooled.
        let noRaw = sim.sweep().map { s -> ScanSample in var s = s; s.rawField = nil; return s }
        XCTAssertTrue(replay(noRaw).contains { $0.level > .none })
    }

    // MARK: - Must detect

    func testPlainScrew_detectedWheneverPhysicsAllows_andNearTheScrew() {
        var detectedFacings = 0
        for facing in facings {
            var sim = SweepSimulator()
            sim.wallFacing = facing
            sim.wobbleDegrees = 5
            let readings = replay(sim.sweep())
            let xs = positions(sim)
            let hits = zip(xs, readings).filter { $0.1.level > .none }.map(\.0)
            let peak = sim.truePeak()

            if peak >= 1.5 * ScanDetector.Config().cautionThreshold {
                XCTAssertFalse(hits.isEmpty, "missed a screw facing \(facing)° (true peak \(peak) µT)")
            }
            for x in hits {
                XCTAssertLessThan(abs(x), 30, "detection \(x) mm from the screw facing \(facing)°")
            }
            if !hits.isEmpty { detectedFacings += 1 }
        }
        // Earth's field direction decides how strongly a plain screw magnetises
        // relative to the sweep, so not every wall direction is detectable — but
        // most should be.
        XCTAssertGreaterThanOrEqual(detectedFacings, 5)
    }

    func testPlainScrew_wasInvisibleToTheOneOhDetector() {
        // North-facing wall, the plain screw's best case.
        let readings = replay(SweepSimulator().sweep())
        XCTAssertTrue(readings.contains { $0.level > .none })
        let legacyPeak = readings.map(\.legacyDeviation).max() ?? 0
        XCTAssertEqual(MagnetometerManager.classify(deviation: legacyPeak, sensitivity: 1), .safe)
        // Even at the 1.0 slider's maximum it stays invisible.
        XCTAssertEqual(MagnetometerManager.classify(deviation: legacyPeak, sensitivity: 2), .safe)
    }

    func testMagnetisedScrew_detectedOnEveryWall() {
        for facing in facings {
            var sim = SweepSimulator()
            sim.wallFacing = facing
            sim.remanence = 60_000
            XCTAssertTrue(replay(sim.sweep()).contains { $0.level > .none },
                          "missed a magnetised screw facing \(facing)°")
        }
    }

    func testHoveringOverScrew_neverFadesToClear() {
        let sim = SweepSimulator()
        // Approach, then hold over the screw for 30 seconds.
        let approach = (0..<300).map { -150 + Double($0) * 0.5 }
        let readings = replay(sim.run(path: approach + Array(repeating: 0, count: 3_000)))
        let holding = readings.suffix(3_000)
        XCTAssertTrue(holding.allSatisfy { $0.level > .none }, "detection faded while held over the screw")
    }

    func testDeeperScrew_stillSeenAtHigherSensitivity() {
        var sim = SweepSimulator()
        sim.depth = 25   // plaster skim over board: ~1.9 µT, under the default threshold
        var detector = ScanDetector()
        XCTAssertFalse(replay(sim.sweep(), detector: detector).contains { $0.level > .none })
        detector.sensitivity = 2
        XCTAssertTrue(replay(sim.sweep(), detector: detector).contains { $0.level > .none })
    }

    // MARK: - Trust gates

    func testUncalibratedCompass_blocksScanning_thenRecovers() {
        let sim = SweepSimulator()
        var samples = sim.sweep()
        for i in 0..<300 { samples[i].accuracy = -1 }
        let readings = replay(samples)
        XCTAssertTrue(readings.prefix(300).allSatisfy { $0.status == .needsMotionCalibration && $0.level == .none })
        XCTAssertEqual(readings.last?.status, .scanning)
        XCTAssertTrue(readings.contains { $0.level > .none }, "should recalibrate and still find the screw")
    }

    func testMagSafeAccessory_flagsImplausibleBaseline() {
        var sim = SweepSimulator()
        sim.inducedVolume = 0
        sim.accessoryField = SIMD3(0, 0, -150)
        let last = replay(sim.sweep()).last
        XCTAssertEqual(last?.warnings.contains(.implausibleBaseline), true)

        sim.accessoryField = .zero
        XCTAssertEqual(replay(sim.sweep()).last?.warnings.contains(.implausibleBaseline), false)
    }

    func testLowAccuracy_isReported() {
        var samples = SweepSimulator().sweep()
        for i in samples.indices { samples[i].accuracy = 0 }
        XCTAssertEqual(replay(samples).last?.warnings.contains(.lowAccuracy), true)
    }

    // MARK: - Behaviour

    func testPeakPassed_signalledAfterCrossingTheScrew() {
        var sim = SweepSimulator()
        sim.remanence = 60_000
        let readings = replay(sim.sweep())
        let xs = positions(sim)
        let passed = zip(xs, readings).filter { $0.1.peakPassed }.map(\.0)
        XCTAssertFalse(passed.isEmpty)
        XCTAssertTrue(passed.allSatisfy { $0 > 0 }, "said 'passed' before reaching the screw")
    }

    func testHysteresis_noChatterAtThreshold() {
        var detector = ScanDetector()
        let baseline = SIMD3<Double>(0, 20, -45)
        var changes = 0
        var last = ScanDetector.Level.none
        var rng = SplitMix(seed: 9)
        for i in 0..<2_000 {
            // Hovering right at the caution threshold with noise.
            let offset = i < 100 ? 0 : 3.0 + rng.gaussian() * 0.3
            let s = ScanSample(time: Double(i) / 100, field: baseline + SIMD3(offset, 0, 0),
                               rawField: nil, rotationRate: .zero, accuracy: 2)
            let level = detector.process(s).level
            if level != last { changes += 1; last = level }
        }
        XCTAssertLessThanOrEqual(changes, 2)
    }

    func testSensitivity_scalesThresholds() {
        var d = ScanDetector()
        d.sensitivity = 2
        XCTAssertEqual(d.cautionLevel, 1.5, accuracy: 1e-9)
        XCTAssertEqual(d.dangerLevel, 6, accuracy: 1e-9)
    }

    // MARK: - Recordings

    /// Real sweep, iPhone 17 Pro, a plain screw under a hardback book, two passes.
    /// Truth from the raw sensor: still and rotating 0–3.3 s, passes peaking near
    /// 4.5 s and 9.5 s, back at the start point from ~11.5 s.
    func testRecording_plainScrewUnderBook() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/plain-screw-book-iphone17pro.csv")
        let samples = ScanRecording.samples(fromCSV: try String(contentsOf: url, encoding: .utf8))
        XCTAssertEqual(samples.count, 1324)
        let t0 = samples[0].time
        let readings = replay(samples)
        let timed = zip(samples.map { $0.time - t0 }, readings)
        func during(_ range: ClosedRange<Double>) -> [ScanDetector.Reading] {
            timed.filter { range.contains($0.0) }.map(\.1)
        }

        // Rotating up to ~27°/s before the sweep must not read as metal.
        XCTAssertFalse(during(0...3.3).contains { $0.level > .none })
        XCTAssertTrue(during(3.7...5.0).contains { $0.level > .none }, "missed the first pass")
        XCTAssertTrue(during(9.2...10.5).contains { $0.level > .none }, "missed the second pass")
        // iOS's calibrated field ends 41 µT out here; ours must come back clean.
        XCTAssertTrue(during(11.8...13.5).allSatisfy { $0.level == .none && $0.deviation < 2 })

        // 1.0 read under its 25 µT caution threshold on the first pass.
        let legacyFirstPass = during(3.7...5.0).map(\.legacyDeviation).max() ?? 0
        XCTAssertEqual(MagnetometerManager.classify(deviation: legacyFirstPass, sensitivity: 1), .safe)
    }

    func testCSV_roundTripsAndIgnoresMetadata() {
        let csv = """
        # device: iPhone17,1
        # item: plain screw
        t,bx,by,bz,acc,rx,ry,rz,wx,wy,wz,qx,qy,qz,qw,gx,gy,gz
        0.00,1.5,20.25,-44.8,2,100,200,300,0.01,0,-0.02,0,0,0,1,0,-1,0
        0.01,1.6,20.30,-44.7,1,,,,0,0,0,0,0,0,1,0,-1,0
        """
        let samples = ScanRecording.samples(fromCSV: csv)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].field, SIMD3(1.5, 20.25, -44.8))
        XCTAssertEqual(samples[0].rawField, SIMD3(100, 200, 300))
        XCTAssertEqual(samples[0].rotationRate, SIMD3(0.01, 0, -0.02))
        XCTAssertNil(samples[1].rawField)
        XCTAssertEqual(samples[1].accuracy, 1)
    }

    func testMedian() {
        XCTAssertEqual(ScanDetector.median([3, 1, 2]), 2)
        XCTAssertEqual(ScanDetector.median([4, 1, 3, 2]), 2.5)
    }
}
