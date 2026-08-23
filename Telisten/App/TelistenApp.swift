import SwiftUI

@main
struct TelistenApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task { await model.start() }
                .frame(minWidth: 360, minHeight: 560)
        }
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
            }
        }
        #endif
    }
}
