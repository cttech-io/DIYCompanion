<p align="center">
  <img src="DIYCompanion/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" alt="DIY Companion">
</p>

<h1 align="center">DIY Companion</h1>

<p align="center">
  A free, ad-free iOS utility app for everyday DIY tasks.<br>
  Five precision tools in one lightweight app.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17%2B-blue?logo=apple" alt="iOS 17+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-lightgrey?logo=swift" alt="SwiftUI">
  <img src="https://img.shields.io/badge/license-cttech.io%20Open%20License-green" alt="cttech.io Open License">
</p>

---

## Tools

### 🔵 Spirit Level
Uses the iPhone's accelerometer to display a real-time bubble level. Works flat on a surface or held vertically against a wall. Automatically adapts to portrait and landscape orientation. Haptic feedback fires the moment the device is perfectly level.

### 📡 Wall Scanner
Uses the iPhone's magnetometer to detect metal objects behind walls — studs, screws, pipes, and wiring. Automatically calibrates to the ambient magnetic field on launch so readings are relative to your environment, not Earth's field. Adjustable sensitivity slider for different wall materials and conditions. Haptic pulses fire as the reading crosses into the caution and danger bands, so you can keep your eyes on the wall while sweeping.

> **Note:** Remove MagSafe accessories before scanning. The ring magnets will interfere with readings. Run a fresh calibration before each scan.

### 🔦 Torch / Flashlight
Fine-grained brightness control over the rear camera flash — useful for inspecting dark spaces under stairs, behind panels, or in ceiling voids. The tool name adapts to your device language: *Torch* for British English, *Flashlight* for US English.

### 🔊 Noise Meter
Uses the iPhone's microphone to measure ambient sound levels in real time. Displays an approximate dB SPL reading, a colour-coded tier badge (Quiet / Moderate / Loud / Dangerous), and a resettable peak level marker. Useful for checking noise levels on a job site or inside a room before and after insulation work.

### 📏 Ruler
Turns the iPhone screen into a calibrated physical ruler. Uses a per-device PPI lookup table to ensure accurate tick marks in both centimetres and inches. Automatically switches the ruler from the left edge (portrait) to the top edge (landscape) so the longest side of the phone is always used.

Tap anywhere on the ruler to place a measurement marker. Tap again to place a second marker. Drag either marker to reposition. When both markers are set, the span between them is calculated automatically. Tap **Copy** to copy the measurement to the clipboard.

---

## Requirements

- iOS 17+
- Physical device required for Wall Scanner (magnetometer not available in Simulator)
- Microphone permission required for Noise Meter

## Tech Stack

| Framework | Used for |
|-----------|----------|
| SwiftUI | All UI |
| CoreMotion | Accelerometer (spirit level), magnetometer (wall scanner) |
| AVFoundation | Torch control, microphone metering (noise meter) |
| UIKit | Haptic feedback, screen PPI metrics |

## Building

Open `DIYCompanion.xcodeproj` in Xcode 15 or later and run on a connected device.

## License

[cttech.io Open License](LICENSE) — source available for personal and educational use; commercial distribution (including App Store submission) requires written permission from cttech.io.
