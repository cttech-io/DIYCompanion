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
            let level: Bool
            if abs(gz) > 0.4 {
                level = abs(gx) < threshold && abs(gy) < threshold
            } else {
                switch self.deviceOrientation {
                case .landscapeLeft, .landscapeRight:
                    level = abs(gy) < threshold
                default:
                    level = abs(gx) < threshold
                }
            }

            if level != self.isLevel {
                self.isLevel = level
                if level { self.haptic.impactOccurred() }
            }
        }
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

    @Published var deviation: Double = 0.0   // µT above calibrated baseline
    @Published var threat: Threat = .safe
    @Published var sensitivity: Double = 1.0
    @Published var isCalibrating: Bool = false

    enum Threat { case safe, caution, danger }

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

            // Thresholds are in deviation µT; sensitivity scales them down/up.
            // Default (1.0×): caution at 25 µT, danger at 60 µT.
            let caution = 25.0 / self.sensitivity
            let danger  = 60.0 / self.sensitivity
            self.threat = dev > danger ? .danger : dev > caution ? .caution : .safe
        }
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

    func start() {
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

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement)
        try? session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diynoise.caf")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else { return }
        rec.isMeteringEnabled = true
        rec.record()
        recorder = rec
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let r = recorder else { return }
        r.updateMeters()
        let raw = r.averagePower(forChannel: 0)   // dBFS −160…0
        // iPhone mic clips near 120 dB SPL at 0 dBFS, giving a usable SPL approximation.
        let spl = max(30.0, min(120.0, Double(raw) + 120.0))
        decibels = Float(spl)
        peak = max(peak, decibels)
        switch raw {
        case ..<(-70): tier = .quiet       // < ~50 dB SPL
        case ..<(-50): tier = .moderate    // ~50–70 dB SPL
        case ..<(-30): tier = .loud        // ~70–90 dB SPL
        default:       tier = .dangerous   // > ~90 dB SPL
        }
    }

    func resetPeak() { peak = decibels }

    func stop() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit { stop() }
}

class TorchManager: ObservableObject {
    @Published var intensity: Float = 0.0 {
        didSet { apply(intensity) }
    }

    func stop() { intensity = 0 }

    private func apply(_ level: Float) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        if level > 0 {
            try? device.setTorchModeOn(level: max(0.001, min(level, 1.0)))
        } else {
            device.torchMode = .off
        }
        device.unlockForConfiguration()
    }
}
