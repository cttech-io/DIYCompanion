# DIY Companion

A free, ad-free iOS utility app for everyday DIY tasks. Three precision tools in one lightweight app.

## Tools

### Spirit Level
Uses the iPhone's accelerometer to display a real-time bubble level. Works flat on a surface or held vertically against a wall. Automatically adapts to portrait and landscape orientation. Haptic feedback fires the moment the device is perfectly level.

### Wall Scanner
Uses the iPhone's magnetometer to detect metal objects behind walls — studs, screws, pipes, and wiring. Automatically calibrates to the ambient magnetic field on launch so readings are relative to your environment, not Earth's field. Adjustable sensitivity slider for different wall materials and conditions.

> **Note:** Remove MagSafe accessories before scanning. The ring magnets will interfere with readings. Run a fresh calibration before each scan.

### Torch / Flashlight
Fine-grained brightness control over the rear camera flash — useful for inspecting dark spaces under stairs, behind panels, or in ceiling voids. The tool name adapts to your device language: *Torch* for British English, *Flashlight* for US English.

## Requirements

- iOS 17+
- Physical device required for Wall Scanner (magnetometer not available in Simulator)

## Tech Stack

- SwiftUI
- CoreMotion — accelerometer, gyroscope, magnetometer via `CMDeviceMotion`
- AVFoundation — torch control
- UIKit — haptic feedback

## Building

Open `DIYCompanion.xcodeproj` in Xcode 15 or later and run on a connected device.

## License

MIT
