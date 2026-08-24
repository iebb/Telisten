import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    Toggle("Show chats", isOn: $model.showChats)
                    Text("Playlists, favorites, and downloads remain visible when chats are hidden.")
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
        .task { await model.refreshCacheUsage() }
    }

    private var cacheLimit: Binding<Int64> {
        Binding(
            get: { model.cacheLimitBytes },
            set: { model.setCacheLimit($0) }
        )
    }
}
