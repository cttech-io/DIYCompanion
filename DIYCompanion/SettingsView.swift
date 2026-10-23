import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified   // Follow the OS.
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Apply the chosen appearance app-wide by overriding every window's
    /// interface style. iOS 18+ broke SwiftUI's `preferredColorScheme` (it will
    /// not revert out of dark), so we drive `overrideUserInterfaceStyle`
    /// directly. Call this from where the change originates (the Settings
    /// picker) and at launch — an @AppStorage `onChange` outside the Settings
    /// sheet does not fire reliably across the sheet boundary.
    static func apply(_ raw: String) {
        let style = AppAppearance(rawValue: raw)?.uiStyle ?? .unspecified
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = style }
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.appearance)     private var appearance:     String = Prefs.defaultAppearance
    @AppStorage(Prefs.useMetric)      private var useMetric:      Bool   = true
    @AppStorage(Prefs.hapticsEnabled) private var hapticsEnabled: Bool   = true
    @Environment(\.dismiss)           private var dismiss

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    appearanceCard
                    measurementCard
                    feedbackCard
                    aboutCard
                }
                .padding()
            }
            .background(Color(.secondarySystemBackground))
            .onChange(of: appearance) { _, newValue in
                // Applied here, from inside the sheet, so it fires reliably.
                AppAppearance.apply(newValue)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Cards

    private var appearanceCard: some View {
        card("Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme")
                    .font(.subheadline)
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var measurementCard: some View {
        card("Measurement") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Default Units")
                    .font(.subheadline)
                Picker("Units", selection: $useMetric) {
                    Text("Metric (cm)").tag(true)
                    Text("Imperial (in)").tag(false)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var feedbackCard: some View {
        card("Feedback") {
            Toggle(isOn: $hapticsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Haptic Feedback")
                        .font(.subheadline)
                    Text("A tap you can feel when the spirit level reaches level, and when the wall scanner finds metal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.accentColor)
        }
    }

    private var aboutCard: some View {
        card("About") {
            VStack(spacing: 0) {
                HStack {
                    Text("DIY Companion")
                        .font(.subheadline)
                    Spacer()
                    Text("v\(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Divider().padding(.vertical, 14)

                linkRow(label: "Developer", value: "cttech.io",
                        url: URL(string: "https://cttech.io")!)

                Divider().padding(.vertical, 14)

                linkRow(label: "Source Code", value: "GitHub",
                        url: URL(string: "https://github.com/cttech-io/DIYCompanion")!)

                Divider().padding(.vertical, 14)

                linkRow(label: "Privacy Policy", value: "cttech.io",
                        url: URL(string: "https://cttech.io/diy-companion/privacy-policy/")!)

                Divider().padding(.vertical, 14)

                HStack {
                    Text("Licence")
                        .font(.subheadline)
                    Spacer()
                    Text("cttech.io Open License")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption).bold()
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
                .padding(16)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func linkRow(label: String, value: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("\(label): \(value)")
        .accessibilityHint("Opens in browser")
    }
}

// MARK: - Settings toolbar

private struct SettingsModifier: ViewModifier {
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
    }
}

extension View {
    func withSettingsToolbar() -> some View {
        modifier(SettingsModifier())
    }
}
