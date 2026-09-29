import SwiftUI

@main
struct TelistenApp: App {
    @State private var model = AppModel()
    @State private var startupTask: Task<Void, Never>?
    #if os(macOS)
    @AppStorage("floatingLyrics.locked") private var lyricsLocked = false
    #endif

    var body: some Scene {
        WindowGroup(id: "library") {
            RootView(model: model)
                .task { await startIfNeeded() }
                #if os(visionOS)
                .frame(minWidth: 760, minHeight: 560)
                #else
                .frame(minWidth: 360, minHeight: 560)
                #endif
        }
        #if os(visionOS)
        .defaultSize(width: 1_080, height: 720)
        .windowResizability(.contentMinSize)
        #endif
        #if os(macOS)
        .defaultSize(width: 1_080, height: 720)
        .commands {
            CommandMenu("Playback") {
                Button(model.player.isPlaying ? "Pause" : "Play") { model.player.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Previous") { model.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Button("Next") { model.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Divider()
                OpenLyricsWindowButton()
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Toggle("Lock Floating Lyrics", isOn: $lyricsLocked)
            }
        }
        #endif

        #if os(macOS) || os(visionOS)
        // A stable value brings the existing lyrics window forward on repeated opens.
        WindowGroup("Floating Lyrics", id: LyricsWindow.id, for: String.self) { _ in
            FloatingLyricsView(model: model)
                .task { await startIfNeeded() }
        } defaultValue: {
            LyricsWindow.currentPlayback
        }
        .windowResizability(.contentSize)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultPosition(.bottom)
        #endif
        #if os(visionOS)
        .windowStyle(.plain)
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.utilityPanel)
        }
        #endif
        #endif
    }

    @MainActor
    private func startIfNeeded() async {
        if startupTask == nil {
            startupTask = Task { await model.start() }
        }
        await startupTask?.value
    }
}
