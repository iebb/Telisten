import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    #if DEBUG && (os(macOS) || os(visionOS))
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Group {
            if model.canOpenLibrary {
                LibraryView(model: model)
            } else {
                LoginView(model: model)
            }
        }
        .tint(.telistenAccent)
        #if DEBUG && (os(macOS) || os(visionOS))
        .task {
            if ProcessInfo.processInfo.arguments.contains("--demo-floating-lyrics") {
                openWindow(id: LyricsWindow.id, value: LyricsWindow.currentPlayback)
            }
        }
        #endif
        .alert("Error", isPresented: errorIsPresented) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}
