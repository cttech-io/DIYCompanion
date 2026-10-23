import SwiftUI
import CoreMotion
import simd

// Scanner Lab: an internal tool for tuning the Scanner 2.0 detector. It shows
// the new detector next to the 1.0 reading and records 100 Hz sensor sweeps to
// CSV, shared only through the share sheet — nothing leaves the phone otherwise.
// Visible in Debug and TestFlight builds only.

enum ScannerLab {
    /// Must be false in any build submitted to the App Store: App Review runs
    /// sandbox builds, so the TestFlight check alone would show it to them.
    static let isEnabled = true

    static var isAvailable: Bool {
        #if DEBUG
        return isEnabled
        #else
        return isEnabled && Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    static let items = ["Blank wall", "Plain screw", "Magnetised screw", "Nail",
                        "Nail plate / steel stud", "Copper pipe", "Plastic pipe",
                        "Cable", "Find sensor", "Other"]
}

final class ScannerLabModel: ObservableObject {
    struct TracePoint: Identifiable {
        let id: Int
        let deviation: Double
        let legacy: Double
    }

    @Published private(set) var reading = ScanDetector.Reading(
        status: .calibrating, level: .none, deviation: 0, legacyDeviation: 0,
        peak: 0, peakPassed: false, warnings: [])
    @Published private(set) var trace: [TracePoint] = []
    @Published private(set) var baselineStrength = 0.0
    @Published private(set) var accuracy = -1
    @Published private(set) var biasCorrections = 0
    @Published private(set) var isRecording = false
    @Published private(set) var recordedSamples = 0
    @Published private(set) var recordings: [URL] = []
    @Published var sensitivity = 1.0 {
        didSet { let s = sensitivity; queue.addOperation { self.detector.sensitivity = s } }
    }

    static let traceLength = 180   // 6 s at the 30 Hz publish rate

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    private var recordingItem = ""

    // Owned by `queue`.
    private var detector = ScanDetector()
    private var rows: [String] = []
    private var recording = false
    private var sampleIndex = 0

    init() { refreshRecordings() }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.01
        motion.magnetometerUpdateInterval = 0.01
        // Raw magnetometer is pulled per sample rather than pushed, so each row
        // pairs the calibrated field with the freshest raw reading.
        motion.startMagnetometerUpdates()
        motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.handle(data)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        motion.stopMagnetometerUpdates()
        if isRecording { stopRecording() }
    }

    func recalibrate() {
        queue.addOperation { self.detector.recalibrate() }
    }

    func startRecording(item: String, notes: String) {
        recordingItem = item
        let header = metadata(item: item, notes: notes) + [ScanRecording.columns.joined(separator: ",")]
        queue.addOperation {
            self.rows = header
            self.recording = true
        }
        isRecording = true
        recordedSamples = 0
    }

    func stopRecording() {
        isRecording = false
        let item = recordingItem
        queue.addOperation {
            self.recording = false
            let text = self.rows.joined(separator: "\n") + "\n"
            self.rows = []
            let url = Self.directory.appendingPathComponent(Self.fileName(item: item))
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            DispatchQueue.main.async { self.refreshRecordings() }
        }
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refreshRecordings()
    }

    // MARK: - Sensor queue

    private func handle(_ data: CMDeviceMotion) {
        let f = data.magneticField.field
        let raw = motion.magnetometerData?.magneticField
        let r = data.rotationRate
        let sample = ScanSample(
            time: data.timestamp,
            field: SIMD3(f.x, f.y, f.z),
            rawField: raw.map { SIMD3($0.x, $0.y, $0.z) },
            rotationRate: SIMD3(r.x, r.y, r.z),
            accuracy: Int(data.magneticField.accuracy.rawValue))
        let result = detector.process(sample)

        if recording {
            let q = data.attitude.quaternion
            let g = data.gravity
            let rawCells = raw.map { [$0.x, $0.y, $0.z].map(Self.cell) } ?? ["", "", ""]
            let cells = [String(format: "%.4f", data.timestamp)]
                + [f.x, f.y, f.z].map(Self.cell) + [String(sample.accuracy)]
                + rawCells
                + [r.x, r.y, r.z, q.x, q.y, q.z, q.w, g.x, g.y, g.z].map(Self.cell)
            rows.append(cells.joined(separator: ","))
        }

        sampleIndex += 1
        guard sampleIndex % 3 == 0 else { return }   // publish at ~33 Hz
        let point = TracePoint(id: sampleIndex, deviation: result.deviation, legacy: result.legacyDeviation)
        let strength = detector.baselineStrength
        let corrections = detector.biasCorrections
        let count = max(rows.count - 1, 0)
        DispatchQueue.main.async {
            self.reading = result
            self.baselineStrength = strength
            self.accuracy = sample.accuracy
            self.biasCorrections = corrections
            if self.isRecording { self.recordedSamples = count }
            self.trace.append(point)
            if self.trace.count > Self.traceLength { self.trace.removeFirst(self.trace.count - Self.traceLength) }
        }
    }

    // MARK: - Files

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScannerLab", isDirectory: true)
    }

    private static func cell(_ v: Double) -> String { String(format: "%.4f", v) }

    private static func fileName(item: String) -> String {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let slug = item.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "\(stamp)-\(String(slug)).csv"
    }

    private func refreshRecordings() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        recordings = urls.filter { $0.pathExtension == "csv" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func metadata(item: String, notes: String) -> [String] {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let info = Bundle.main.infoDictionary
        let config = ScanDetector.Config()
        return [
            "# item: \(item)",
            "# notes: \(notes.replacingOccurrences(of: "\n", with: " "))",
            "# device: \(model)",
            "# ios: \(UIDevice.current.systemVersion)",
            "# app: \(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))",
            "# sensitivity: \(sensitivity)",
            "# thresholds: caution \(config.cautionThreshold) danger \(config.dangerThreshold)",
            "# recorded: \(Date().formatted(.iso8601))",
        ]
    }
}

struct ScannerLabView: View {
    @StateObject private var model = ScannerLabModel()
    @State private var item = ScannerLab.items[1]
    @State private var notes = ""

    var body: some View {
        List {
            Section {
                readout
                TraceView(points: model.trace,
                          caution: ScanDetector.Config().cautionThreshold / model.sensitivity,
                          danger: ScanDetector.Config().dangerThreshold / model.sensitivity)
                    .frame(height: 160)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                HStack {
                    Text("Sensitivity")
                    Slider(value: $model.sensitivity, in: 0.5...2.0)
                    Text(String(format: "%.1fx", model.sensitivity)).monospacedDigit()
                }
                Button("Calibrate") { model.recalibrate() }
            } footer: {
                Text("Orange: new detector. Grey: what 1.0 shows. Dashed lines: caution and danger.")
            }

            Section("Recording") {
                Picker("Item", selection: $item) {
                    ForEach(ScannerLab.items, id: \.self) { Text($0) }
                }
                .disabled(model.isRecording)
                TextField("Notes (depth, wall direction, case…)", text: $notes, axis: .vertical)
                    .disabled(model.isRecording)
                Button {
                    if model.isRecording {
                        model.stopRecording()
                    } else {
                        model.startRecording(item: item, notes: notes)
                    }
                } label: {
                    Label(model.isRecording ? "Stop (\(model.recordedSamples) samples)" : "Start Recording",
                          systemImage: model.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(model.isRecording ? Color.statusRedText : Color.accentText)
                }
            }

            Section {
                if model.recordings.isEmpty {
                    Text("No recordings yet").foregroundStyle(.secondary)
                } else {
                    ShareLink("Share All (\(model.recordings.count))", items: model.recordings)
                        .foregroundStyle(Color.accentText)
                    ForEach(model.recordings, id: \.self) { url in
                        ShareLink(item: url) {
                            Text(url.lastPathComponent).font(.footnote.monospaced())
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in offsets.map { model.recordings[$0] }.forEach(model.delete) }
                }
            } header: {
                Text("Recordings")
            } footer: {
                Text("Stand-in for plasterboard: a hardback book or chopping board about 12 mm thick. Calibrate with the phone flat on it away from the item, record, then slide slowly across the item and back two or three times. Repeat with the book turned 90°.")
            }
        }
        .navigationTitle("Scanner Lab")
        .navigationBarTitleDisplayMode(.inline)
        .keepsScreenAwake()
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f", model.reading.deviation))
                    .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                Text("µT").foregroundStyle(.secondary)
                Spacer()
                Text(levelLabel).font(.headline).foregroundStyle(levelColor)
            }
            Group {
                Text(String(format: "1.0 reading %.1f µT · peak %.1f%@", model.reading.legacyDeviation,
                            model.reading.peak, model.reading.peakPassed ? " (passed)" : ""))
                Text(String(format: "Baseline %.1f µT · compass %@ · bias fixes %d",
                            model.baselineStrength, accuracyLabel, model.biasCorrections))
                if !model.reading.warnings.isEmpty {
                    Text(warningText).foregroundStyle(Color.statusOrangeText)
                }
            }
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private var levelLabel: String {
        switch model.reading.status {
        case .calibrating: return "Calibrating"
        case .needsMotionCalibration: return "Move in a figure-8"
        case .scanning:
            switch model.reading.level {
            case .none: return "Nothing"
            case .caution: return "Caution"
            case .danger: return "Danger"
            }
        }
    }

    private var levelColor: Color {
        switch model.reading.level {
        case .none: return .secondary
        case .caution: return .statusOrangeText
        case .danger: return .statusRedText
        }
    }

    private var accuracyLabel: String {
        switch model.accuracy {
        case 2: return "high"
        case 1: return "medium"
        case 0: return "low"
        default: return "uncalibrated"
        }
    }

    private var warningText: String {
        model.reading.warnings.map { w -> String in
            switch w {
            case .lowAccuracy: return "low compass accuracy"
            case .implausibleBaseline: return "baseline not Earth-like (magnet nearby?)"
            case .largeRotation: return "rotated a lot — recalibrate"
            }
        }
        .sorted().joined(separator: " · ")
    }
}

private struct TraceView: View {
    let points: [ScannerLabModel.TracePoint]
    let caution: Double
    let danger: Double

    var body: some View {
        Canvas { context, size in
            let top = max(danger * 1.2, points.map { max($0.deviation, $0.legacy) }.max() ?? 0)
            func y(_ v: Double) -> CGFloat { size.height * (1 - CGFloat(min(v / top, 1))) }
            func x(_ i: Int) -> CGFloat {
                size.width * CGFloat(i) / CGFloat(ScannerLabModel.traceLength - 1)
            }
            for level in [caution, danger] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(level)))
                line.addLine(to: CGPoint(x: size.width, y: y(level)))
                context.stroke(line, with: .color(.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            let offset = ScannerLabModel.traceLength - points.count
            for (value, color) in [(\ScannerLabModel.TracePoint.legacy, Color.secondary),
                                   (\ScannerLabModel.TracePoint.deviation, Color.accentColor)] {
                var path = Path()
                for (i, p) in points.enumerated() {
                    let pt = CGPoint(x: x(i + offset), y: y(p[keyPath: value]))
                    i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                context.stroke(path, with: .color(color), lineWidth: 2)
            }
        }
        .accessibilityLabel("Signal trace")
    }
}
