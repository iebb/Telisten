#if os(macOS) || os(visionOS)
import SwiftUI
#if os(macOS)
import AppKit
#endif

enum LyricsWindow {
    static let id = "floating-lyrics"
    static let currentPlayback = "current-playback"
}

struct OpenLyricsWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("floatingLyrics.locked") private var isLocked = false

    var body: some View {
        Button("Floating Lyrics", systemImage: "rectangle.on.rectangle") {
            // Opening from the app is also the recovery path for a click-through overlay.
            isLocked = false
            openWindow(id: LyricsWindow.id, value: LyricsWindow.currentPlayback)
        }
        .help("Open or unlock the floating lyrics window")
        .accessibilityIdentifier("lyrics.openWindow")
    }
}

struct FloatingLyricsView: View {
    @Bindable var model: AppModel
    private var preferences = FloatingLyricsPreferences()
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var isHovering = false
    @State private var showsSettings = false
    @State private var plainLineIndex = 0
    #if os(macOS)
    @State private var windowController = LyricsOverlayWindowController()
    #endif

    private var lyrics: TrackLyrics? {
        guard let track = model.player.track, case let .loaded(value) = model.lyricsState,
              value.trackID == track.id else { return nil }
        return value
    }

    private var excerpt: FloatingLyricExcerpt? {
        lyrics.map { FloatingLyricExcerpt(lyrics: $0, time: model.player.currentTime, plainLineIndex: plainLineIndex) }
    }

    private var showsControls: Bool {
        #if os(macOS)
        !preferences.isLocked && isHovering
        #else
        true // Gaze users need discoverable controls without relying on pointer hover.
        #endif
    }

    private var controlsAreAccessible: Bool {
        showsControls || (voiceOverEnabled && !preferences.isLocked)
    }

    private var overlayHeight: Double {
        let lines = preferences.doubleLine ? 2.0 : 1.0
        let pagingHeight = (excerpt?.plainLineCount ?? 0) > 1 ? 24.0 : 0
        return 64 + preferences.safeFontSize * 1.45 * lines + (preferences.showTitle ? 22 : 0) + pagingHeight
    }

    var body: some View {
        VStack(spacing: 6) {
            controls
                .opacity(showsControls ? 1 : 0)
                // Keep controls available to VoiceOver without forcing the bar onscreen.
                .allowsHitTesting(controlsAreAccessible || showsSettings)
                .accessibilityHidden(!controlsAreAccessible)
            lyricContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(preferences.safeTextOpacity)
            if preferences.showTitle {
                Text(trackTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(width: preferences.safeWidth, height: overlayHeight)
        .background {
            RoundedRectangle(cornerRadius: 14)
                // AppKit passes mouse events through completely transparent pixels.
                // A visually transparent floor keeps hover and background dragging usable.
                .fill(.black.opacity(max(preferences.safeBackgroundOpacity, 0.01)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(showsControls ? 0.12 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onChange(of: model.player.track?.id) { _, _ in plainLineIndex = 0 }
        .onChange(of: lyrics?.matchKey) { _, _ in plainLineIndex = 0 }
        .onChange(of: preferences.isLocked) { _, locked in
            if locked { isHovering = false; showsSettings = false }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Floating Lyrics")
        #if os(macOS)
        .ignoresSafeArea()
        .containerBackground(.clear, for: .window)
        .background {
            LyricsOverlayWindow(
                controller: windowController,
                keepsOnTop: preferences.keepsOnTop,
                isLocked: preferences.isLocked
            )
        }
        #endif
    }

    private var trackTitle: String {
        guard let track = model.player.track else { return "Telisten · Floating Lyrics" }
        return "\(track.displayTitle) — \(track.displayArtist)"
    }

    private var controls: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            Image(systemName: "circle.grid.2x2.fill")
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .help("Drag to move lyrics")
                .accessibilityLabel("Move lyrics window")
            #endif
            Text(trackTitle)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Previous", systemImage: "backward.fill") { model.previous() }
                .disabled(model.player.track == nil)
            Button(model.player.isPlaying ? "Pause" : "Play", systemImage: model.player.isPlaying ? "pause.fill" : "play.fill") {
                model.player.toggle()
            }
            .disabled(model.player.track == nil || model.player.isLoading)
            Button("Next", systemImage: "forward.fill") { model.next() }
                .disabled(model.player.track == nil)
            if model.lyricsCandidates.count > 1 { matchMenu }
            Button("Customize Lyrics", systemImage: "slider.horizontal.3") { showsSettings.toggle() }
                .accessibilityIdentifier("lyrics.customize")
                .popover(isPresented: $showsSettings) { FloatingLyricsSettingsView() }
            #if os(macOS)
            Button("Center Horizontally on Current Screen", systemImage: "align.horizontal.center") {
                windowController.centerHorizontally()
            }
            .help("Center lyrics on this display without changing their vertical position")
            .accessibilityIdentifier("lyrics.centerHorizontally")
            Toggle(isOn: preferences.$keepsOnTop) {
                Label("Keep on Top", systemImage: preferences.keepsOnTop ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .help("Keep lyrics above other windows")
            .accessibilityIdentifier("lyrics.keepOnTop")
            Button("Lock Lyrics", systemImage: "lock.open") { preferences.isLocked = true }
                .help("Pass clicks through lyrics. Reopen Floating Lyrics or press ⇧⌘L to unlock.")
                .accessibilityIdentifier("lyrics.lock")
            #endif
            Button("Close Lyrics", systemImage: "xmark") {
                dismissWindow(id: LyricsWindow.id, value: LyricsWindow.currentPlayback)
            }
            .accessibilityIdentifier("lyrics.close")
        }
        .font(.system(size: 13, weight: .medium))
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.white.opacity(0.9))
        .tint(.white)
        .frame(height: 32)
        .padding(.horizontal, 8)
        .background(.black.opacity(0.78), in: Capsule())
    }

    private var matchMenu: some View {
        Menu {
            ForEach(model.lyricsCandidates, id: \.matchKey) { candidate in
                Button {
                    model.selectLyrics(candidate)
                } label: {
                    Label(
                        "\(candidate.isSynced ? "Timed" : "Plain") · \(candidate.matchedAlbum ?? candidate.source) · \(candidate.matchedDuration.map(DisplayFormat.duration) ?? "Unknown length")",
                        systemImage: candidate.matchKey == lyrics?.matchKey ? "checkmark" : "text.quote"
                    )
                }
            }
        } label: {
            Label("Choose Lyrics", systemImage: "text.quote")
        }
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private var lyricContent: some View {
        if model.player.track == nil {
            status("Play a song to see its lyrics", symbol: "music.note")
        } else if let excerpt, let lyrics {
            VStack(spacing: 4) {
                if let current = excerpt.current {
                    lyricLine(current, color: Color(lyricsRGB: preferences.activeRGB))
                } else {
                    status(excerpt.next == nil ? "No lyrics found" : "♪", symbol: nil)
                }
                if preferences.doubleLine {
                    if let next = excerpt.next {
                        lyricLine(next, color: Color(lyricsRGB: preferences.upcomingRGB))
                    } else {
                        Text(" ").font(preferences.font).accessibilityHidden(true)
                    }
                }
                if !lyrics.isSynced, excerpt.plainLineCount > 1 {
                    HStack(spacing: 12) {
                        Button("Previous lyric", systemImage: "chevron.left") { plainLineIndex = max(0, plainLineIndex - 1) }
                            .disabled(plainLineIndex == 0)
                        Text("Untimed · \(plainLineIndex + 1)/\(excerpt.plainLineCount)")
                            .font(.caption.monospacedDigit())
                        Button("Next lyric", systemImage: "chevron.right") { plainLineIndex += 1 }
                            .disabled(plainLineIndex >= excerpt.plainLineCount - 1)
                    }
                    .font(.caption)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white)
                }
            }
        } else {
            switch model.lyricsState {
            case .idle, .loading, .loaded:
                status("Finding lyrics…", symbol: "text.quote")
            case .unavailable:
                status("No lyrics found", symbol: "music.note")
            case .failed:
                status("Lyrics unavailable", symbol: "wifi.exclamationmark")
            }
        }
    }

    private func lyricLine(_ line: LyricLine, color: Color) -> some View {
        Button {
            if let time = line.time { model.player.seek(to: time) }
        } label: {
            Text(line.text)
                .font(preferences.font)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .multilineTextAlignment(preferences.textAlignment)
                .frame(maxWidth: .infinity, alignment: preferences.alignment)
                .modifier(LyricTextOutline(enabled: preferences.outline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(line.time == nil)
        .accessibilityHint(line.time.map { "Seek to \(DisplayFormat.duration($0))" } ?? "Untimed lyrics")
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }

    private func status(_ title: String, symbol: String?) -> some View {
        HStack(spacing: 10) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.system(size: min(preferences.safeFontSize, 24), weight: .semibold, design: .rounded))
        .foregroundStyle(Color(lyricsRGB: preferences.activeRGB))
        .modifier(LyricTextOutline(enabled: preferences.outline))
        .frame(maxWidth: .infinity)
    }
}

#if os(macOS)
@MainActor
private final class LyricsOverlayWindowController {
    weak var window: NSWindow?

    func centerHorizontally() {
        // Use this window's display, including its origin in a multi-display desktop.
        guard let window, let screen = window.screen else { return }
        let origin = NSPoint(x: screen.frame.midX - window.frame.width / 2, y: window.frame.minY)
        window.setFrameOrigin(origin)
    }
}

private struct LyricsOverlayWindow: NSViewRepresentable {
    let controller: LyricsOverlayWindowController
    let keepsOnTop: Bool
    let isLocked: Bool

    func makeNSView(context: Context) -> WindowObserver {
        let view = WindowObserver()
        view.controller = controller
        return view
    }

    func updateNSView(_ view: WindowObserver, context: Context) {
        view.controller = controller
        view.keepsOnTop = keepsOnTop
        view.isLocked = isLocked
        view.configureWindow()
    }

    final class WindowObserver: NSView {
        var controller: LyricsOverlayWindowController?
        var keepsOnTop = true
        var isLocked = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            controller?.window = window
            guard let window else { return }
            window.level = keepsOnTop ? .floating : .normal
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            // Keep a titled window's keyboard focus without visible title-bar chrome.
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            window.isExcludedFromWindowsMenu = false
            window.isMovable = !isLocked
            window.isMovableByWindowBackground = !isLocked
            window.ignoresMouseEvents = isLocked
            window.collectionBehavior.insert(.fullScreenAuxiliary)
        }
    }
}
#endif
#endif
