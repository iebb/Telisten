import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .ready:
                LibraryView(model: model)
            case .connecting:
                LaunchView()
            case .signedOut, .code, .emailAddress, .emailVerification, .password:
                LoginView(model: model)
            }
        }
        .tint(.telistenAccent)
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

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: 18) {
            ArtworkTile(symbol: "waveform", size: 78)
            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.telistenBackground)
    }
}
