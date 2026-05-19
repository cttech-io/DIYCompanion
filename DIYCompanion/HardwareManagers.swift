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

    private let filter: Double = 0.15

    init() {
        haptic.prepare()
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let attitude = data?.attitude else { return }
            let p = attitude.pitch * (180 / Double.pi)
            let r = attitude.roll  * (180 / Double.pi)
            self.pitch = p * self.filter + self.pitch * (1 - self.filter)
            self.roll  = r * self.filter + self.roll  * (1 - self.filter)
            let level = abs(self.pitch) < 0.5 && abs(self.roll) < 0.5
            if level != self.isLevel {
                self.isLevel = level
                if level { self.haptic.impactOccurred() }
            }
        }
    }

    deinit { motionManager.stopDeviceMotionUpdates() }
}

class MagnetometerManager: ObservableObject {
    private let motionManager = CMMotionManager()

    @Published var strength: Double = 0.0
    @Published var threat: Threat = .safe

    enum Threat {
        case safe, caution, danger
    }

    init() {
        guard motionManager.isMagnetometerAvailable else { return }
        motionManager.magnetometerUpdateInterval = 1.0 / 30.0
        motionManager.startMagnetometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let f = data?.magneticField else { return }
            let mag = sqrt(f.x * f.x + f.y * f.y + f.z * f.z)
            self.strength = mag
            self.threat = mag > 250 ? .danger : mag > 120 ? .caution : .safe
        }
    }

    deinit { motionManager.stopMagnetometerUpdates() }
}

class TorchManager: ObservableObject {
    @Published var intensity: Float = 0.0 {
        didSet { apply(intensity) }
    }

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
