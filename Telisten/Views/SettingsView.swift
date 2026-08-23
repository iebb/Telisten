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
                    Text("Downloaded tracks are kept in a 2 GB least-recently-used cache.")
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
    }
}
