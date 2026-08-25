import SwiftUI

struct ListenTogetherView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                switch model.listenTogetherState {
                case .idle:
                    introduction
                case .preparing:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing group audio…")
                    }
                case let .failed(message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                case let .live(session):
                    liveSession(session)
                }

                if !isLive {
                    Section("Groups and channels") {
                        ForEach(filteredChats) { chat in
                            chatRow(chat)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Find a group or channel")
            .navigationTitle("Listen Together")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private var introduction: some View {
        Section {
            Label {
                Text("Start from the current track, or join an existing Telisten session. People using Telegram can listen in the group audio chat without Telisten.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Color.telistenAccent)
            }
        }
    }

    private func liveSession(_ session: ListenTogetherSession) -> some View {
        Section("Live") {
            HStack(spacing: 12) {
                ChatAvatar(model: model, chat: session.chat, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.chat.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(session.role == .host ? "Broadcasting from this device" : "Listening in sync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("\(session.call.participantCount)", systemImage: "person.2.fill")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let presence = session.presence {
                VStack(alignment: .leading, spacing: 3) {
                    Text(presence.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text("\(presence.artist) · \(DisplayFormat.duration(presence.elapsed))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Button(session.role == .host ? "End for everyone" : "Leave session", role: .destructive) {
                Task {
                    await model.stopListenTogether(endHostedCall: true)
                    dismiss()
                }
            }
        }
    }

    private func chatRow(_ chat: MusicChat) -> some View {
        HStack(spacing: 11) {
            ChatAvatar(model: model, chat: chat, size: 34)
            Text(chat.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Join") {
                Task { await model.joinListenTogether(in: chat) }
            }
            .buttonStyle(.borderless)
            Button("Start") {
                Task { await model.startListenTogether(in: chat) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.player.track == nil)
        }
        .task { await model.loadAvatar(for: chat) }
    }

    private var filteredChats: [MusicChat] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return model.listenTogetherChats }
        return model.listenTogetherChats.filter {
            $0.title.localizedCaseInsensitiveContains(value)
        }
    }

    private var isLive: Bool {
        if case .live = model.listenTogetherState { return true }
        return false
    }
}
