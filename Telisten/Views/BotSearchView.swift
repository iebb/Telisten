import SwiftUI

struct SearchBotProvidersView: View {
    @Bindable var model: AppModel
    let query: String

    init(model: AppModel, query: String) {
        self.model = model
        self.query = query
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.searchBots.isEmpty {
                emptyConfiguration
            } else {
                Text("Search bots")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                ForEach(Array(model.searchBots.enumerated()), id: \.element.id) { index, config in
                    providerButton(config)
                    if index < model.searchBots.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }

                if normalizedQuery.isEmpty {
                    Text("Enter a song, artist, or album above to search with a bot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 5)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private func providerButton(_ config: SearchBotConfig) -> some View {
        let isActive = model.activeBotSearchConfig?.id == config.id

        return Button {
            Task { await model.beginBotSearch(using: config) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.telistenAccent)
                    .frame(width: 30, height: 30)
                    .background(Color.telistenAccent.opacity(0.10), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Search with \(config.displayBotName)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(config.commandPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                if isActive && model.isBotSearching {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Searching")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(normalizedQuery.isEmpty || model.isBotSearching)
        .opacity(normalizedQuery.isEmpty ? 0.58 : 1)
        .accessibilityLabel("Search with \(config.displayBotName)")
        .accessibilityValue(config.commandPreview)
        .accessibilityHint(normalizedQuery.isEmpty ? "Enter a search term first" : "Sends your search to the Telegram bot")
    }

    private var emptyConfiguration: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "paperplane")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("No search bots configured")
                    .font(.subheadline.weight(.medium))
                Text("Add a Telegram search bot in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BotSearchConversationView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @FocusState private var composerFocused: Bool
    @State private var composerText = ""
    @State private var playlistTrack: Track?

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 9) {
                        if messages.isEmpty && !model.isBotSearching {
                            conversationPlaceholder
                        }

                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }

                        if model.isBotSearching {
                            typingIndicator
                                .id(loadingAnchor)
                        }

                        if let error = model.botSearchError, !error.isEmpty {
                            errorRow(error)
                                .id(errorAnchor)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .background(Color.telistenBackground)
                .onAppear { scrollToLatest(using: proxy, animated: false) }
                .onChange(of: latestContentID) { _, _ in
                    scrollToLatest(using: proxy, animated: true)
                }
            }
            .navigationTitle(model.activeBotSearchConfig?.displayBotName ?? "Search bot")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .sheet(item: $playlistTrack) { track in
                PlaylistSheet(model: model, track: track)
            }
        }
    }

    private var messages: [BotSearchMessage] {
        model.botSearchMessages.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date < $1.date
        }
    }

    @ViewBuilder
    private func messageRow(_ message: BotSearchMessage) -> some View {
        VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 5) {
            if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(message.text)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .foregroundStyle(message.isOutgoing ? Color.white : Color.primary)
                    .background(
                        message.isOutgoing ? Color.telistenAccent : Color.secondary.opacity(0.12),
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 14,
                            bottomLeadingRadius: message.isOutgoing ? 14 : 4,
                            bottomTrailingRadius: message.isOutgoing ? 4 : 14,
                            topTrailingRadius: 14,
                            style: .continuous
                        )
                    )
                    .frame(maxWidth: 520, alignment: message.isOutgoing ? .trailing : .leading)
            }

            if let track = message.track {
                audioRow(track)
                    .frame(maxWidth: 520)
            }

            if !message.buttonRows.isEmpty {
                buttonGrid(message.buttonRows)
                    .frame(maxWidth: 520)
            }

            Text(message.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: message.isOutgoing ? .trailing : .leading)
        .accessibilityElement(children: .contain)
    }

    private func audioRow(_ track: Track) -> some View {
        HStack(spacing: 4) {
            Button {
                model.playBotSearchTrack(track)
            } label: {
                HStack(spacing: 9) {
                    TrackArtwork(model: model, track: track, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(trackMetadata(track))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: model.player.track?.id == track.id && model.player.isPlaying
                          ? "pause.circle.fill"
                          : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.telistenAccent)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(track.displayTitle) by \(track.displayArtist)")

            Button {
                playlistTrack = track
            } label: {
                Image(systemName: "text.badge.plus")
                    .font(.headline)
                    .foregroundStyle(Color.telistenAccent)
                    .frame(width: 34, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(track.displayTitle) to playlist")
            .accessibilityHint("Choose an existing playlist or create a new one")
        }
        .padding(8)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func buttonGrid(_ rows: [[BotSearchButton]]) -> some View {
        VStack(spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row) { button in
                        botButton(button)
                    }
                }
            }
        }
    }

    private func botButton(_ button: BotSearchButton) -> some View {
        Button {
            activate(button)
        } label: {
            HStack(spacing: 4) {
                Text(button.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if case .openURL = button.action {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .controlSize(.small)
        .tint(Color.telistenAccent)
        .disabled(model.isBotSearching || button.action == .unsupported)
        .accessibilityLabel(button.title)
        .accessibilityHint(buttonHint(button))
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Waiting for \(model.activeBotSearchConfig?.displayBotName ?? "bot")…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func errorRow(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityLabel("Search error: \(error)")
    }

    private var conversationPlaceholder: some View {
        ContentUnavailableView(
            "No messages yet",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Search results and bot controls appear here.")
        )
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                TextField("Message \(model.activeBotSearchConfig?.displayBotName ?? "bot")", text: $composerText)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit(sendComposerMessage)
                    .padding(.vertical, 7)
                    .accessibilityLabel("Bot message")

                Button(action: sendComposerMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Color.telistenAccent : Color.secondary.opacity(0.45))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.bar)
        }
    }

    private var canSend: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isBotSearching
    }

    private func sendComposerMessage() {
        let message = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !model.isBotSearching else { return }
        composerText = ""
        Task { await model.sendBotSearchMessage(message) }
    }

    private func activate(_ button: BotSearchButton) {
        switch button.action {
        case let .openURL(url):
            openURL(url)
        case .unsupported:
            break
        default:
            Task { await model.activateBotSearchButton(button) }
        }
    }

    private func buttonHint(_ button: BotSearchButton) -> String {
        switch button.action {
        case .openURL: "Opens a link"
        case .unsupported: "This Telegram button is not supported"
        default: "Sends this choice to the Telegram bot"
        }
    }

    private func trackMetadata(_ track: Track) -> String {
        guard track.duration > 0 else { return track.displayArtist }
        return "\(track.displayArtist)  •  \(DisplayFormat.duration(track.duration))"
    }

    private var latestContentID: String {
        if let error = model.botSearchError, !error.isEmpty { return errorAnchor }
        if model.isBotSearching { return loadingAnchor }
        return messages.last.map {
            "message:\($0.id):\($0.text):\($0.buttonRows.hashValue):\($0.track?.id ?? "")"
        } ?? "empty"
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
        let target: AnyHashable
        if let error = model.botSearchError, !error.isEmpty {
            target = AnyHashable(errorAnchor)
        } else if model.isBotSearching {
            target = AnyHashable(loadingAnchor)
        } else if let lastMessage = messages.last {
            target = AnyHashable(lastMessage.id)
        } else {
            return
        }

        let action = { proxy.scrollTo(target, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.2), action)
        } else {
            action()
        }
    }

    private let loadingAnchor = "bot-search-loading"
    private let errorAnchor = "bot-search-error"
}
