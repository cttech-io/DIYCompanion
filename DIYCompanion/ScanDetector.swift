import Foundation
import simd

/// One magnetometer reading, decoupled from Core Motion so the detector can be
/// driven by live sensors, recorded sweeps and simulations alike.
struct ScanSample: Equatable {
    /// Seconds, any monotonic origin.
    var time: TimeInterval
    /// iOS-calibrated field in the device frame, µT (`CMDeviceMotion.magneticField`).
    var field: SIMD3<Double>
    /// Uncalibrated magnetometer in the device frame, µT (`CMMagnetometerData`).
    /// Preferred source once calibrated; see `ScanDetector`.
    var rawField: SIMD3<Double>?
    /// Bias-corrected gyro in the device frame, rad/s.
    var rotationRate: SIMD3<Double>
    /// `CMMagneticFieldCalibrationAccuracy` raw value: -1 uncalibrated … 2 high.
    var accuracy: Int
}

/// Wall-scanner signal processing ("Scanner 2.0"). Pure value type: no
/// hardware, no clock, so every decision it makes can be unit-tested and
/// replayed from recordings.
///
/// Why it differs from the 1.0 magnitude detector:
/// - It measures the full 3-axis change in field, not the change in strength.
///   `|E + δ| − |E| ≈ δ·Ê` hides any part of a screw's field that is
///   perpendicular to Earth's — often most of it.
/// - Measuring the vector means rotating the phone would also move the reading,
///   so every sample is rotated back into the frame the phone had at
///   calibration using the gyro alone. Earth's field then cancels whatever the
///   phone's orientation. (The gyro, not the magnetometer-corrected attitude:
///   that would partly "correct away" the very metal we're looking for.)
/// - The baseline follows slow drift, but only while the signal is quiet, so
///   holding the phone over a screw never fades back to "nothing here".
/// - iOS's calibrated field can't be trusted mid-sweep: its background compass
///   calibration mistakes a nearby screw for a change in the phone's own
///   magnetism and "corrects" for it. On an iPhone 17 Pro recording it drifted
///   up to 230 µT from the raw sensor and stayed 41 µT out after the phone
///   returned to its start point. So iOS's correction (the phone's hard-iron
///   offset, raw − calibrated) is captured once at calibration and frozen, and
///   from then on the detector reads the raw sensor minus that offset.
struct ScanDetector {

    struct Config {
        var calibrationDuration: TimeInterval = 0.5
        /// Provisional: the 1.0 values (25/60 µT) were above what a screw
        /// behind plasterboard produces. Re-tune from recorded sweeps.
        var cautionThreshold = 3.0
        var dangerThreshold = 12.0
        /// A level is left only once the signal falls below this fraction of
        /// its entry threshold, so noise at the edge can't make it chatter.
        var exitRatio = 0.7
        var medianWindow = 5
        /// Exponential smoothing applied after the median filter (0…1, higher = less smoothing).
        var smoothing = 0.35
        /// The baseline follows drift with this time constant while quiet…
        var driftTimeConstant: TimeInterval = 4
        /// …and much more slowly between quiet and caution, so drift can't creep
        /// out of reach of the baseline and lock in a false reading, while a
        /// weak real signal still takes many seconds to fade.
        var slowDriftTimeConstant: TimeInterval = 20
        /// "Quiet" = below this fraction of the caution threshold.
        var quietFraction = 0.4
        /// Earth's field is ~25–65 µT anywhere on the planet. A baseline outside
        /// this means a magnet (MagSafe, a case) or metal nearby at calibration.
        var plausibleBaseline: ClosedRange<Double> = 20...70
        /// Beyond this rotation since calibration, residual bias errors start to
        /// show; suggest recalibrating.
        var maxRotation = Double.pi / 3
        /// After a peak, the signal falling below this fraction of it means the
        /// phone has moved past the object.
        var peakPassedRatio = 0.6
    }

    enum Status: Equatable {
        case calibrating
        /// iOS reports the compass as uncalibrated; scanning is blocked.
        case needsMotionCalibration
        case scanning
    }

    enum Level: Int, Comparable {
        case none, caution, danger
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    enum Warning: Hashable {
        case lowAccuracy
        case implausibleBaseline
        case largeRotation
    }

    struct Reading: Equatable {
        var status: Status
        var level: Level
        /// µT away from the baseline, independent of sensitivity.
        var deviation: Double
        /// What the 1.0 detector would show for the same sample, for comparison.
        var legacyDeviation: Double
        /// Largest deviation in the current detection, 0 when nothing detected.
        var peak: Double
        /// The phone has moved past the strongest point; the object is behind it.
        var peakPassed: Bool
        var warnings: Set<Warning>
    }

    var config: Config
    /// Scales thresholds down (more sensitive) or up, as the slider does.
    var sensitivity = 1.0

    private(set) var status: Status = .calibrating
    private(set) var level: Level = .none
    private(set) var baseline: SIMD3<Double> = .zero
    private(set) var baselineStrength = 0.0
    /// How far iOS's own calibrated field has wandered from ours, µT. Diagnostic only.
    private(set) var iosDrift = 0.0

    private var orientation = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
    /// The phone's own magnetism (raw − calibrated), frozen at calibration.
    private var hardIron: SIMD3<Double>?
    private var lastTime: TimeInterval?
    private var calibrationStart: TimeInterval?
    private var calibrationSum: SIMD3<Double> = .zero
    private var hardIronSum: SIMD3<Double> = .zero
    private var hardIronCount = 0
    private var calibrationStrengthSum = 0.0
    private var calibrationCount = 0
    private var window: [SIMD3<Double>] = []
    private var smoothed: SIMD3<Double>?
    private var peak = 0.0

    init(config: Config = Config()) {
        self.config = config
    }

    var cautionLevel: Double { config.cautionThreshold / sensitivity }
    var dangerLevel: Double { config.dangerThreshold / sensitivity }

    /// Start over: the phone's current orientation becomes the reference frame.
    mutating func recalibrate() {
        status = .calibrating
        level = .none
        orientation = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        hardIron = nil
        iosDrift = 0
        calibrationStart = nil
        calibrationSum = .zero
        hardIronSum = .zero
        hardIronCount = 0
        calibrationStrengthSum = 0
        calibrationCount = 0
        window = []
        smoothed = nil
        peak = 0
    }

    mutating func process(_ s: ScanSample) -> Reading {
        // Clamp so a stalled sensor or a recording gap can't spin the frame.
        let dt = lastTime.map { min(max(s.time - $0, 0), 0.1) } ?? 0
        lastTime = s.time
        integrateRotation(s.rotationRate, dt: dt)
        let field = sensorField(s)
        let reference = orientation.act(field)

        // An uncalibrated compass can be off by tens of µT and is still being
        // re-estimated; nothing it says can be trusted. Hold until iOS is happy,
        // then calibrate afresh.
        if s.accuracy < 0 {
            if status != .needsMotionCalibration {
                recalibrate()
                status = .needsMotionCalibration
            }
            return reading(deviation: 0, legacy: 0, accuracy: s.accuracy)
        }
        if status == .needsMotionCalibration {
            recalibrate()
        }

        if status == .calibrating {
            calibrationStart = calibrationStart ?? s.time
            calibrationSum += reference
            calibrationStrengthSum += simd_length(s.field)
            calibrationCount += 1
            if let raw = s.rawField {
                hardIronSum += raw - s.field
                hardIronCount += 1
            }
            if s.time - calibrationStart! >= config.calibrationDuration {
                baseline = calibrationSum / Double(calibrationCount)
                baselineStrength = calibrationStrengthSum / Double(calibrationCount)
                // Only trust the raw sensor if it was there for the whole calibration.
                if hardIronCount == calibrationCount {
                    hardIron = hardIronSum / Double(hardIronCount)
                }
                status = .scanning
            }
            return reading(deviation: 0, legacy: 0, accuracy: s.accuracy)
        }

        let filtered = filter(reference)
        let deviation = simd_length(filtered - baseline)
        let legacy = abs(simd_length(s.field) - baselineStrength)

        updateLevel(deviation)
        followDrift(filtered, deviation: deviation, dt: dt)
        return reading(deviation: deviation, legacy: legacy, accuracy: s.accuracy)
    }

    // MARK: - Steps

    private mutating func integrateRotation(_ rotationRate: SIMD3<Double>, dt: TimeInterval) {
        let rate = simd_length(rotationRate)
        guard rate > 0, dt > 0 else { return }
        let step = simd_quatd(angle: rate * dt, axis: rotationRate / rate)
        orientation = simd_normalize(orientation * step)
    }

    /// The external field in the device frame: raw minus the frozen offset
    /// once calibrated, iOS's calibrated field while calibrating or when the
    /// raw sensor is unavailable.
    private mutating func sensorField(_ s: ScanSample) -> SIMD3<Double> {
        guard let hardIron, let raw = s.rawField else { return s.field }
        let field = raw - hardIron
        iosDrift = simd_length(s.field - field)
        return field
    }

    private mutating func filter(_ v: SIMD3<Double>) -> SIMD3<Double> {
        window.append(v)
        if window.count > config.medianWindow { window.removeFirst() }
        let median = SIMD3(
            Self.median(window.map(\.x)),
            Self.median(window.map(\.y)),
            Self.median(window.map(\.z)))
        let next = smoothed.map { $0 + (median - $0) * config.smoothing } ?? median
        smoothed = next
        return next
    }

    private mutating func updateLevel(_ deviation: Double) {
        let caution = cautionLevel, danger = dangerLevel
        let next: Level
        if deviation >= danger || (level == .danger && deviation > danger * config.exitRatio) {
            next = .danger
        } else if deviation >= caution || (level >= .caution && deviation > caution * config.exitRatio) {
            next = .caution
        } else {
            next = .none
        }
        level = next
        peak = next == .none ? 0 : max(peak, deviation)
    }

    private mutating func followDrift(_ filtered: SIMD3<Double>, deviation: Double, dt: TimeInterval) {
        // Frozen during a detection, so holding over metal never fades to clear.
        guard level == .none else { return }
        let tau = deviation < cautionLevel * config.quietFraction
            ? config.driftTimeConstant : config.slowDriftTimeConstant
        baseline += (filtered - baseline) * min(dt / tau, 1)
    }

    private func reading(deviation: Double, legacy: Double, accuracy: Int) -> Reading {
        var warnings = Set<Warning>()
        if accuracy == 0 { warnings.insert(.lowAccuracy) }
        if status == .scanning, !config.plausibleBaseline.contains(simd_length(baseline)) {
            warnings.insert(.implausibleBaseline)
        }
        if 2 * acos(min(abs(orientation.real), 1)) > config.maxRotation {
            warnings.insert(.largeRotation)
        }
        return Reading(
            status: status,
            level: status == .scanning ? level : .none,
            deviation: deviation,
            legacyDeviation: legacy,
            peak: peak,
            peakPassed: peak >= cautionLevel && deviation < peak * config.peakPassedRatio,
            warnings: warnings)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}

// MARK: - Recordings

/// CSV format written by the Scanner Lab and replayed by the tests. Columns are
/// looked up by name, so extra columns (attitude, gravity) are carried along
/// for analysis without the parser needing to know about them.
enum ScanRecording {
    static let columns = ["t", "bx", "by", "bz", "acc", "rx", "ry", "rz",
                          "wx", "wy", "wz", "qx", "qy", "qz", "qw", "gx", "gy", "gz"]

    /// `#`-prefixed lines are metadata (device, item, notes) and are skipped.
    static func samples(fromCSV text: String) -> [ScanSample] {
        var index: [String: Int] = [:]
        var result: [ScanSample] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#") { continue }
            let cells = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if index.isEmpty {
                for (i, name) in cells.enumerated() { index[name] = i }
                continue
            }
            func value(_ name: String) -> Double? {
                guard let i = index[name], i < cells.count else { return nil }
                return Double(cells[i])
            }
            guard let t = value("t"), let bx = value("bx"), let by = value("by"), let bz = value("bz")
            else { continue }
            var raw: SIMD3<Double>?
            if let rx = value("rx"), let ry = value("ry"), let rz = value("rz") { raw = SIMD3(rx, ry, rz) }
            result.append(ScanSample(
                time: t,
                field: SIMD3(bx, by, bz),
                rawField: raw,
                rotationRate: SIMD3(value("wx") ?? 0, value("wy") ?? 0, value("wz") ?? 0),
                accuracy: Int(value("acc") ?? 2)))
        }
        return result
    }
}
