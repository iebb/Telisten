import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var lyricsServerDraft = ""
    @State private var lyricsServerError: String?
    @State private var isApplyingLyricsServer = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    Toggle("Show music sources", isOn: $model.showChats)
                    Text("Playlists, favorites, and downloads remain visible when music sources are hidden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Offline cache") {
                    LabeledContent("Used", value: DisplayFormat.fileSize(model.cacheBytes))
                    Picker("Maximum", selection: cacheLimit) {
                        ForEach(CacheLimits.options, id: \.self) { bytes in
                            Text(DisplayFormat.fileSize(bytes)).tag(bytes)
                        }
                    }
                    Text("Partial streams resume from disk. Oldest cached music is removed when this limit is reached.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("https://lrclib.net", text: $lyricsServerDraft)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .onSubmit { applyLyricsServer() }

                    Button("Apply server") { applyLyricsServer() }
                        .disabled(isApplyingLyricsServer || lyricsServerDraft.isEmpty)

                    Button("Use LRCLIB default") {
                        lyricsServerDraft = LyricsServerConfiguration.defaultAddress
                        applyLyricsServer()
                    }
                    .disabled(isApplyingLyricsServer || model.lyricsServerURL == LyricsServerConfiguration.defaultURL)

                    if let lyricsServerError {
                        Label(lyricsServerError, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Lyrics server")
                } footer: {
                    Text("Use the base URL of an LRCLIB-compatible server. Telisten requests /api/get and /api/search; cached lyrics stay available offline.")
                }
                Section {
                    Button("Sign out of this account", role: .destructive) {
                        Task {
                            await model.logOut()
                            dismiss()
                        }
                    }
                } footer: {
                    Text("Signing out removes this account's MTProto session keys from Keychain. Other accounts stay signed in.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(minWidth: 360, minHeight: 360)
        .task {
            lyricsServerDraft = model.lyricsServerURL.absoluteString
            await model.refreshCacheUsage()
        }
    }

    private var cacheLimit: Binding<Int64> {
        Binding(
            get: { model.cacheLimitBytes },
            set: { model.setCacheLimit($0) }
        )
    }

    private func applyLyricsServer() {
        guard let serverURL = LyricsServerConfiguration.normalizedURL(from: lyricsServerDraft) else {
            lyricsServerError = "Enter a valid HTTPS server URL."
            return
        }
        lyricsServerError = nil
        isApplyingLyricsServer = true
        Task {
            await model.setLyricsServerURL(serverURL)
            lyricsServerDraft = serverURL.absoluteString
            isApplyingLyricsServer = false
        }
    }
}
