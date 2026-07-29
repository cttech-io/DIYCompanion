import Foundation
import CoreMotion
import AVFoundation
import UIKit

class LevelManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private let haptic = UIImpactFeedbackGenerator(style: .heavy)

    @Published var pitch: Double = 0.0
    @Published var roll: Double = 0.0
    @Published var isLevel: Bool = false
    @Published var deviceOrientation: UIDeviceOrientation = .portrait

    // Plumb (against-a-wall) mode: engaged when the phone is held roughly
    // vertical, where attitude-based pitch/roll hit gimbal lock. Driven by
    // gravity instead, so the readout stays well-defined.
    @Published var isPlumbMode: Bool = false
    @Published var plumbAngle: Double = 0.0   // degrees from true vertical

    private let filter: Double = 0.15
    private var orientationToken: NSObjectProtocol?

    init() {
        haptic.prepare()
    }

    func start() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationToken = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let o = UIDevice.current.orientation
            if o.isValidInterfaceOrientation {
                self?.deviceOrientation = o
            }
        }

        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data = data else { return }
            let p = data.attitude.pitch * (180 / Double.pi)
            let r = data.attitude.roll  * (180 / Double.pi)
            self.pitch = p * self.filter + self.pitch * (1 - self.filter)
            self.roll  = r * self.filter + self.roll  * (1 - self.filter)

            // Gravity-based isLevel: works for both flat (on table) and vertical (against wall).
            // When mostly flat (|gz| > 0.4), both lateral axes must be near zero.
            // When vertical, only the axis perpendicular to gravity matters.
            let gx = data.gravity.x
            let gy = data.gravity.y
            let gz = data.gravity.z
            let threshold = 0.0087  // sin(0.5°)
            let plumb = abs(gz) <= 0.4
            self.isPlumbMode = plumb

            let level: Bool
            if !plumb {
                level = abs(gx) < threshold && abs(gy) < threshold
            } else {
                // Drive both the readout and the level state from the SAME angle,
                // so the bubble is centred exactly when it reports plumb.
                let angle = Self.plumbAngleDegrees(gx: gx, gy: gy, orientation: self.deviceOrientation)
                self.plumbAngle = angle * self.filter + self.plumbAngle * (1 - self.filter)
                level = abs(angle) < 0.5   // degrees
            }

            // Keep the haptic engine warm as we approach level; a generator that
            // has gone idle (~a couple of seconds) can silently drop its impact.
            let nearLevel = plumb ? abs(self.plumbAngle) < 3.0
                                  : (abs(gx) < 0.05 && abs(gy) < 0.05)
            if nearLevel && !self.isLevel { self.haptic.prepare() }

            if level != self.isLevel {
                self.isLevel = level
                let hapticsOn = UserDefaults.standard.object(forKey: Prefs.hapticsEnabled) as? Bool ?? true
                if level && hapticsOn {
                    self.haptic.impactOccurred()
                    self.haptic.prepare()   // ready for the next crossing
                }
            }
        }
    }

    /// Signed angle of the phone from true vertical, in degrees, derived from
    /// gravity so it stays well-defined near the poles where attitude pitch/roll
    /// are ambiguous. Projects gravity onto the screen plane (sx = toward screen
    /// right, sy = toward screen top) for the current orientation, then measures
    /// its lean from straight-down. Zero = perfectly plumb.
    static func plumbAngleDegrees(gx: Double, gy: Double, orientation: UIDeviceOrientation) -> Double {
        let sx: Double, sy: Double
        switch orientation {
        case .portraitUpsideDown: sx = -gx; sy = -gy
        case .landscapeLeft:      sx = -gy; sy =  gx
        case .landscapeRight:     sx =  gy; sy = -gx
        default:                  sx =  gx; sy =  gy   // portrait
        }
        return atan2(sx, -sy) * (180.0 / Double.pi)
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        if let token = orientationToken {
            NotificationCenter.default.removeObserver(token)
            orientationToken = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    deinit { motionManager.stopDeviceMotionUpdates() }
}

class MagnetometerManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private let haptic = UIImpactFeedbackGenerator(style: .heavy)

    @Published var deviation: Double = 0.0   // µT above calibrated baseline
    @Published var threat: Threat = .safe
    @Published var sensitivity: Double = 1.0
    @Published var isCalibrating: Bool = false

    // Declaration order defines severity: safe < caution < danger.
    enum Threat: Comparable { case safe, caution, danger }

    init() {
        haptic.prepare()
    }

    // Baseline is a scalar magnitude, not a vector.
    // Magnitude is rotation-invariant: rotating the phone doesn't change
    // sqrt(x²+y²+z²), so orientation changes produce zero deviation.
    // We use the device-motion calibrated field so iOS has already removed
    // the phone's own hard-iron bias (speaker magnets, etc.) before we start.
    private var baselineMag: Double = 0.0
    private var calibBuf: [Double] = []
    private let calibrationCount = 30  // 1 second at 30 Hz

    func start() {
        beginCalibration()
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] data, _ in
            guard let self, let data = data else { return }

            let f   = data.magneticField.field
            let mag = sqrt(f.x * f.x + f.y * f.y + f.z * f.z)

            if self.isCalibrating {
                self.calibBuf.append(mag)
                if self.calibBuf.count >= self.calibrationCount {
                    self.baselineMag = self.calibBuf.reduce(0.0, +) / Double(self.calibrationCount)
                    self.calibBuf    = []
                    self.isCalibrating = false
                }
                return
            }

            let dev = abs(mag - self.baselineMag)
            self.deviation = dev
            let newThreat = Self.classify(deviation: dev, sensitivity: self.sensitivity)

            // Keep the haptic engine warm as the reading approaches the caution
            // threshold; a generator that has gone idle can silently drop its
            // impact (same pattern as LevelManager).
            if newThreat == .safe, dev > 0.7 * Self.baseCaution / self.sensitivity {
                self.haptic.prepare()
            }

            if newThreat != self.threat {
                let escalated = newThreat > self.threat
                self.threat = newThreat
                let hapticsOn = UserDefaults.standard.object(forKey: Prefs.hapticsEnabled) as? Bool ?? true
                // Buzz on escalation only (safe→caution, caution→danger) so a
                // sweep pulses as it crosses metal without chattering on the
                // way back down.
                if escalated && hapticsOn {
                    self.haptic.impactOccurred(intensity: newThreat == .danger ? 1.0 : 0.7)
                    self.haptic.prepare()   // ready for the next crossing
                }
            }
        }
    }

    /// Thresholds are in deviation µT; sensitivity scales them down/up.
    /// Default (1.0×): caution at 25 µT, danger at 60 µT.
    static let baseCaution = 25.0
    static let baseDanger  = 60.0

    static func classify(deviation dev: Double, sensitivity: Double) -> Threat {
        let caution = baseCaution / sensitivity
        let danger  = baseDanger  / sensitivity
        return dev > danger ? .danger : dev > caution ? .caution : .safe
    }

    func recalibrate() {
        beginCalibration()
    }

    private func beginCalibration() {
        isCalibrating = true
        deviation     = 0
        threat        = .safe
        calibBuf      = []
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    deinit { motionManager.stopDeviceMotionUpdates() }
}

class NoiseManager: ObservableObject {
    enum Tier { case quiet, moderate, loud, dangerous }

    @Published var decibels: Float = 30      // approx dB SPL, clamped 30–120
    @Published var peak: Float = 30
    @Published var tier: Tier = .quiet
    @Published var permissionDenied: Bool = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var interruptionObserver: NSObjectProtocol?
    private var deadTicks = 0   // consecutive ticks reading the dead-recorder floor

    func start() {
        registerInterruptionObserver()
        switch AVAudioApplication.shared.recordPermission {
        case .granted:     beginRecording()
        case .denied:      permissionDenied = true
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.beginRecording() }
                    else { self?.permissionDenied = true }
                }
            }
        @unknown default: break
        }
    }

    /// Re-check on foreground: recover a recorder that an interruption left
    /// dead, and pick up a permission the user granted in Settings while away.
    func restartIfNeeded() {
        // Only act if the meter was actually running (stop() nils the recorder
        // on tab switch) or is recovering from a denial. scenePhase onChange
        // fires even when this tab isn't frontmost, and rebuilding here would
        // re-activate the mic from another tool — showing the mic indicator and
        // re-silencing haptics app-wide via the .record category.
        guard recorder != nil || permissionDenied else { return }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            if permissionDenied { permissionDenied = false }
            // Always rebuild: an interrupted AVAudioRecorder keeps reporting
            // isRecording == true while producing only the −160 dBFS floor, so
            // we can't trust that flag to decide whether a restart is needed.
            beginRecording()
        case .denied:
            permissionDenied = true
        case .undetermined:
            break
        @unknown default:
            break
        }
    }

    private func registerInterruptionObserver() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            // On `.ended`, rebuild immediately (fast path). We deliberately do
            // NOT tear the timer down on `.began`: keeping it alive lets tick()'s
            // watchdog self-heal even if `.ended` is never delivered (a common
            // outcome for Siri, which resigns the app without a clean resume).
            if type == .ended {
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        // Tear down any prior recorder/timer so repeated calls (interruption
        // end, foreground restart) don't stack.
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement)
        try? session.setActive(true)
        // Metering works without persisting audio; write to /dev/null so nothing
        // is ever stored (no unbounded temp file — and a cleaner privacy story).
        let url = URL(fileURLWithPath: "/dev/null")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else { return }
        rec.isMeteringEnabled = true
        rec.record()
        recorder = rec
        deadTicks = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let r = recorder else { return }
        r.updateMeters()
        let raw = r.averagePower(forChannel: 0)   // dBFS −160…0

        // Watchdog: after an interruption the recorder can report isRecording ==
        // true yet only ever return the −160 dBFS floor. A real mic never sits
        // at the floor (even a quiet room is ~−60), so a run of floor readings
        // means the recorder is dead — rebuild it. This self-heals the freeze
        // regardless of whether an `.ended` interruption notification arrives.
        if raw <= -159 || !r.isRecording {
            deadTicks += 1
            if deadTicks >= 5 { beginRecording() }
            return
        }
        deadTicks = 0

        // iPhone mic clips near 120 dB SPL at 0 dBFS, giving a usable SPL approximation.
        let spl = max(30.0, min(120.0, Double(raw) + 120.0))
        decibels = Float(spl)
        peak = max(peak, decibels)
        tier = Self.tier(forDBFS: raw)
    }

    /// Map raw dBFS average power to a coarse tier.
    static func tier(forDBFS raw: Float) -> Tier {
        switch raw {
        case ..<(-70): return .quiet       // < ~50 dB SPL
        case ..<(-50): return .moderate    // ~50–70 dB SPL
        case ..<(-30): return .loud        // ~70–90 dB SPL
        default:       return .dangerous   // > ~90 dB SPL
        }
    }

    func resetPeak() { peak = decibels }

    func stop() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        if let token = interruptionObserver {
            NotificationCenter.default.removeObserver(token)
            interruptionObserver = nil
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        // A `.record` category silences UIFeedbackGenerator haptics app-wide, and
        // the category persists after deactivation — which was killing the Spirit
        // Level's haptic once the Noise Meter had been opened. Reset to a
        // haptic-friendly category on the way out.
        try? session.setCategory(.ambient)
    }

    deinit { stop() }
}

class TorchManager: ObservableObject {
    @Published var intensity: Float = 0.0 {
        didSet { apply(intensity) }
    }

    // Cache the capture device once rather than looking it up on every tick.
    private lazy var device: AVCaptureDevice? = {
        let dev = AVCaptureDevice.default(for: .video)
        return (dev?.hasTorch == true) ? dev : nil
    }()

    func stop() { intensity = 0 }

    private func apply(_ level: Float) {
        guard let device else { return }
        try? device.lockForConfiguration()
        if level > 0 {
            try? device.setTorchModeOn(level: max(0.001, min(level, 1.0)))
        } else {
            device.torchMode = .off
        }
        device.unlockForConfiguration()
    }
}
