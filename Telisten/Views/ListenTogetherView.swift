import SwiftUI

struct ListenTogetherView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var inviteLink: URL?
    @State private var inviteLinkChatID: String?
    @State private var inviteLinkError: String?
    @State private var isLoadingInviteLink = false
    @State private var showContactPicker = false

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
                    Section("Admin groups and channels") {
                        if filteredChats.isEmpty {
                            Label(
                                query.isEmpty ? "No rooms you administer" : "No matching admin rooms",
                                systemImage: "person.badge.key"
                            )
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredChats) { chat in
                                chatRow(chat)
                            }
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
        .sheet(isPresented: $showContactPicker) {
            if let session = liveSessionValue {
                ListenTogetherContactPicker(model: model, session: session)
            }
        }
        .task(id: liveSessionValue?.call.id) {
            guard let session = liveSessionValue else {
                inviteLink = nil
                inviteLinkChatID = nil
                inviteLinkError = nil
                return
            }
            await loadInviteLink(for: session.chat)
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--demo-listen-together-contacts") {
                showContactPicker = true
            }
        }
        #endif
    }

    private var introduction: some View {
        Section {
            Label {
                Text("Choose a group or channel you administer. People using Telegram can listen in the group audio chat without Telisten.")
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

            if let inviteLink, inviteLinkChatID == session.chat.id {
                ShareLink(
                    item: inviteLink,
                    subject: Text(session.chat.title),
                    message: Text("Join \(session.chat.title) to listen together.")
                ) {
                    Label("Share invite link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if isLoadingInviteLink {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing invite link…")
                        .foregroundStyle(.secondary)
                }
            } else if let inviteLinkError {
                Button {
                    Task { await loadInviteLink(for: session.chat, reload: true) }
                } label: {
                    Label(inviteLinkError, systemImage: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
            }

            if session.chat.canInviteUsers == true {
                Button {
                    showContactPicker = true
                } label: {
                    Label("Invite Telegram contacts", systemImage: "person.badge.plus")
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
            .disabled(model.player.track == nil || chat.canManageCalls != true)
            .accessibilityHint(
                chat.canManageCalls == true
                    ? "Starts a Telegram group audio stream"
                    : "This admin role cannot manage group calls"
            )
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

    private var liveSessionValue: ListenTogetherSession? {
        guard case let .live(session) = model.listenTogetherState else { return nil }
        return session
    }

    private func loadInviteLink(for chat: MusicChat, reload: Bool = false) async {
        if !reload, inviteLinkChatID == chat.id, inviteLink != nil { return }
        inviteLink = nil
        inviteLinkChatID = chat.id
        inviteLinkError = nil
        isLoadingInviteLink = true
        defer { isLoadingInviteLink = false }
        do {
            inviteLink = try await model.listenTogetherInviteLink(for: chat)
        } catch {
            inviteLinkError = UserFacingError.message(for: error)
        }
    }
}
