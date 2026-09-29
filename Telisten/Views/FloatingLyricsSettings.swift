#if os(macOS) || os(visionOS)
import SwiftUI

struct FloatingLyricsPreferences: DynamicProperty {
    @AppStorage("floatingLyrics.fontSize") var fontSize = 32.0
    @AppStorage("floatingLyrics.fontDesign") var fontDesign = "rounded"
    @AppStorage("floatingLyrics.bold") var bold = true
    @AppStorage("floatingLyrics.doubleLine") var doubleLine = true
    @AppStorage("floatingLyrics.alignment") var alignmentName = "center"
    @AppStorage("floatingLyrics.activeColor") var activeRGB = 0xFF625F
    @AppStorage("floatingLyrics.upcomingColor") var upcomingRGB = 0xFFFFFF
    @AppStorage("floatingLyrics.textOpacity") var textOpacity = 1.0
    @AppStorage("floatingLyrics.backgroundOpacity") var backgroundOpacity = 0.0
    @AppStorage("floatingLyrics.outline") var outline = true
    @AppStorage("floatingLyrics.showTitle") var showTitle = false
    @AppStorage("floatingLyrics.width") var width = 760.0
    @AppStorage("lyricsWindowKeepsOnTop") var keepsOnTop = true
    @AppStorage("floatingLyrics.locked") var isLocked = false

    var safeFontSize: Double { min(max(fontSize, 18), 64) }
    var safeWidth: Double { min(max(width, 480), 1_200) }
    var safeTextOpacity: Double { min(max(textOpacity, 0.25), 1) }
    var safeBackgroundOpacity: Double { min(max(backgroundOpacity, 0), 1) }

    var font: Font {
        let design: Font.Design = switch fontDesign {
        case "serif": .serif
        case "monospaced": .monospaced
        case "system": .default
        default: .rounded
        }
        return .system(size: safeFontSize, weight: bold ? .bold : .medium, design: design)
    }

    var textAlignment: TextAlignment {
        switch alignmentName {
        case "leading": .leading
        case "trailing": .trailing
        default: .center
        }
    }

    var alignment: Alignment {
        switch alignmentName {
        case "leading": .leading
        case "trailing": .trailing
        default: .center
        }
    }

    func resetAppearance() {
        fontSize = 32
        fontDesign = "rounded"
        bold = true
        doubleLine = true
        alignmentName = "center"
        activeRGB = 0xFF625F
        upcomingRGB = 0xFFFFFF
        textOpacity = 1
        backgroundOpacity = 0
        outline = true
        showTitle = false
        width = 760
    }
}

extension Color {
    init(lyricsRGB: Int) {
        self.init(
            .sRGB,
            red: Double((lyricsRGB >> 16) & 255) / 255,
            green: Double((lyricsRGB >> 8) & 255) / 255,
            blue: Double(lyricsRGB & 255) / 255,
            opacity: 1
        )
    }
}

/// A small dark edge keeps text readable over bright apps even with no backdrop.
struct LyricTextOutline: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .shadow(color: enabled ? .black.opacity(0.9) : .clear, radius: 1, x: 1, y: 0)
            .shadow(color: enabled ? .black.opacity(0.9) : .clear, radius: 1, x: -1, y: 0)
            .shadow(color: enabled ? .black.opacity(0.9) : .clear, radius: 1, x: 0, y: 1)
            .shadow(color: enabled ? .black.opacity(0.9) : .clear, radius: 1, x: 0, y: -1)
    }
}

struct FloatingLyricsSettingsView: View {
    private var preferences = FloatingLyricsPreferences()
    @Environment(\.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Lyrics Appearance").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(16)
            Form {
                Section("Layout") {
                    Picker("Lines", selection: preferences.$doubleLine) {
                        Text("Single").tag(false)
                        Text("Double").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Picker("Alignment", selection: preferences.$alignmentName) {
                        Text("Left").tag("leading")
                        Text("Center").tag("center")
                        Text("Right").tag("trailing")
                    }
                    settingSlider("Width", value: preferences.$width, range: 480...1_200, step: 20, suffix: " pt")
                    Toggle("Show song title", isOn: preferences.$showTitle)
                }
                Section("Typography") {
                    Picker("Font", selection: preferences.$fontDesign) {
                        Text("System").tag("system")
                        Text("Rounded").tag("rounded")
                        Text("Serif").tag("serif")
                        Text("Monospaced").tag("monospaced")
                    }
                    settingSlider("Size", value: preferences.$fontSize, range: 18...64, step: 1, suffix: " pt")
                    Toggle("Bold", isOn: preferences.$bold)
                    Toggle("Text outline", isOn: preferences.$outline)
                }
                Section("Colors") {
                    HStack {
                        Text("Presets")
                        Spacer()
                        preset("Coral", active: 0xFF625F, upcoming: 0xFFFFFF)
                        preset("Mint", active: 0x6EE7B7, upcoming: 0xE2FFF5)
                        preset("Gold", active: 0xFFD166, upcoming: 0xFFF4D6)
                        preset("White", active: 0xFFFFFF, upcoming: 0xAAB4C8)
                    }
                    ColorPicker("Current line", selection: colorBinding(preferences.$activeRGB), supportsOpacity: false)
                    ColorPicker("Next line", selection: colorBinding(preferences.$upcomingRGB), supportsOpacity: false)
                    settingSlider("Text opacity", value: preferences.$textOpacity, range: 0.25...1, step: 0.05, percent: true)
                    settingSlider("Background", value: preferences.$backgroundOpacity, range: 0...1, step: 0.05, percent: true)
                }
                #if os(macOS)
                Section {
                    Toggle("Keep on Top", isOn: preferences.$keepsOnTop)
                    Text("Hover to reveal controls. Drag the grip to move lyrics. Locking lets clicks pass through; choose Floating Lyrics in the app or press ⇧⌘L to unlock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif
                Button("Reset Appearance") { preferences.resetAppearance() }
                    .accessibilityIdentifier("lyrics.resetAppearance")
            }
            .formStyle(.grouped)
        }
        .frame(width: 380, height: 600)
        .preferredColorScheme(.dark)
    }

    private func settingSlider(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>,
        step: Double, suffix: String = "", percent: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * (percent ? 100 : 1)).rounded()))\(percent ? "%" : suffix)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step) { Text(title) }
                .labelsHidden()
                .accessibilityIdentifier("lyrics.setting.\(title)")
        }
    }

    private func preset(_ name: String, active: Int, upcoming: Int) -> some View {
        Button {
            preferences.activeRGB = active
            preferences.upcomingRGB = upcoming
        } label: {
            Circle().fill(Color(lyricsRGB: active))
                .frame(width: 22, height: 22)
                .overlay {
                    if preferences.activeRGB == active && preferences.upcomingRGB == upcoming {
                        Circle().stroke(.white, lineWidth: 2).padding(-3)
                    }
                }
                .padding(4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) colors")
        .help(name)
    }

    private func colorBinding(_ storage: Binding<Int>) -> Binding<Color> {
        Binding(
            get: { Color(lyricsRGB: storage.wrappedValue) },
            set: { color in
                let resolved = color.resolve(in: environment)
                let red = Int((min(max(resolved.red, 0), 1) * 255).rounded())
                let green = Int((min(max(resolved.green, 0), 1) * 255).rounded())
                let blue = Int((min(max(resolved.blue, 0), 1) * 255).rounded())
                storage.wrappedValue = (red << 16) | (green << 8) | blue
            }
        )
    }
}
#endif
