import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var lyricsServerDraft = ""
    @State private var lyricsServerError: String?
    @State private var isApplyingLyricsServer = false
    #if DEBUG
    @State private var editingSearchBot: SearchBotConfig?
    #endif

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
                #if DEBUG
                Section {
                    ForEach(model.searchBots) { config in
                        searchBotRow(config)
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { index in
                            model.searchBots.indices.contains(index) ? model.searchBots[index].id : nil
                        }
                        for id in ids { model.deleteSearchBot(id: id) }
                    }
                    .onMove(perform: model.moveSearchBots)

                    Button {
                        editingSearchBot = SearchBotConfig(botName: "")
                    } label: {
                        Label("Add search bot", systemImage: "plus")
                    }
                } header: {
                    Text("Bot search")
                } footer: {
                    Text("Debug-only bot searches are stored in iCloud Keychain. No bot is included by default.")
                }
                #endif
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
                #if DEBUG && os(iOS)
                if model.searchBots.count > 1 {
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                }
                #endif
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 360)
        #endif
        .task {
            lyricsServerDraft = model.lyricsServerURL.absoluteString
            await model.refreshCacheUsage()
        }
        #if DEBUG
        .sheet(item: $editingSearchBot) { config in
            SearchBotEditorView(model: model, config: config)
        }
        #endif
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

    #if DEBUG
    @ViewBuilder
    private func searchBotRow(_ config: SearchBotConfig) -> some View {
        HStack(spacing: 10) {
            Button {
                editingSearchBot = config
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "message.badge.waveform")
                        .font(.body)
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Search with \(config.displayBotName)")
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("Send \(config.searchPrefix)query\(config.searchSuffix) to bot")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit", systemImage: "pencil") {
                    editingSearchBot = config
                }
                if let index = model.searchBots.firstIndex(where: { $0.id == config.id }) {
                    Button("Move up", systemImage: "arrow.up") {
                        model.moveSearchBots(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                    }
                    .disabled(index == model.searchBots.startIndex)
                    Button("Move down", systemImage: "arrow.down") {
                        model.moveSearchBots(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                    }
                    .disabled(index == model.searchBots.index(before: model.searchBots.endIndex))
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    model.deleteSearchBot(id: config.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("Options for \(config.displayBotName)")
        }
    }
    #endif
}

#if DEBUG
private struct SearchBotEditorView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private let id: UUID
    private let isNew: Bool
    @State private var botName: String
    @State private var searchPrefix: String
    @State private var searchSuffix: String
    @State private var validationError: String?

    init(model: AppModel, config: SearchBotConfig) {
        self.model = model
        id = config.id
        isNew = !model.searchBots.contains { $0.id == config.id }
        _botName = State(initialValue: config.botName)
        _searchPrefix = State(initialValue: config.searchPrefix)
        _searchSuffix = State(initialValue: config.searchSuffix)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("@your_search_bot", text: $botName)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .textContentType(.username)
                        #endif
                } header: {
                    Text("Bot name")
                } footer: {
                    Text("Enter the bot’s Telegram username. The leading @ is optional.")
                }

                Section("Search command") {
                    TextField("Prefix (optional)", text: $searchPrefix)
                        .autocorrectionDisabled()
                    TextField("Suffix (optional)", text: $searchSuffix)
                        .autocorrectionDisabled()
                }

                Section("Preview") {
                    LabeledContent("Message") {
                        Text(searchPrefix + "SEKAI NO OWARI" + searchSuffix)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    Text("Search results open as a simple bot conversation, including the bot’s interactive buttons.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let validationError {
                    Section {
                        Label(validationError, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "Add Search Bot" : "Edit Search Bot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(botName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 360)
        #endif
    }

    private func save() {
        let config = SearchBotConfig(
            id: id,
            botName: botName,
            searchPrefix: searchPrefix,
            searchSuffix: searchSuffix
        )
        if let error = model.upsertSearchBot(config) {
            validationError = error
        } else {
            dismiss()
        }
    }
}
#endif
