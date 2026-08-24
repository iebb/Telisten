import SwiftUI

struct NowPlayingView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case lyrics = "Lyrics"
        case comments = "Comments"
        case queue = "Up Next"
        var id: Self { self }
    }

    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .lyrics

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                hero
                timeline
                controls
                quickActions
                Picker("Now playing section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 22)

                Group {
                    switch section {
                    case .lyrics: LyricsPanel(model: model)
                    case .comments: CommentsPanel(model: model)
                    case .queue: queue
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 4)
            .background(Color.telistenBackground)
            .navigationTitle("Now Playing")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 620)
        .sheet(isPresented: $model.showPlaylistSheet) {
            if let track = model.playlistTrack {
                PlaylistSheet(model: model, track: track)
            }
        }
        .task(id: model.player.track?.id) {
            guard let track = model.player.track else { return }
            async let lyrics: Void = model.loadLyrics(for: track)
            async let comments: Void = model.loadComments(for: track)
            _ = await (lyrics, comments)
        }
    }

    private var hero: some View {
        HStack(spacing: 16) {
            if let track = model.player.track {
                TrackArtwork(model: model, track: track, size: 92, fallbackSymbol: "waveform")
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 7)
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.displayTitle)
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text(track.displayArtist)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
    }

    private var timeline: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { model.player.currentTime }, set: { model.player.seek(to: $0) }),
                in: 0...max(model.player.duration, 1)
            )
            HStack {
                Text(DisplayFormat.duration(model.player.currentTime))
                Spacer()
                Text("−\(DisplayFormat.duration(max(0, model.player.duration - model.player.currentTime)))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 26)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button {
                model.player.toggleMute()
            } label: {
                Image(systemName: model.player.volumeSymbolName)
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(model.player.isMuted ? Color.telistenAccent : .secondary)
            .accessibilityLabel(model.player.isMuted ? "Unmute" : "Mute")

            Spacer(minLength: 12)

            HStack(spacing: 30) {
                Button("Previous", systemImage: "backward.fill") { model.previous() }
                    .labelStyle(.iconOnly)
                if model.player.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(width: 52, height: 52)
                        .accessibilityLabel("Loading track")
                } else {
                    Button(
                        model.player.isPlaying ? "Pause" : "Play",
                        systemImage: model.player.isPlaying ? "pause.circle.fill" : "play.circle.fill"
                    ) { model.player.toggle() }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 52))
                }
                Button("Next", systemImage: "forward.fill") { model.next() }
                    .labelStyle(.iconOnly)
            }

            Spacer(minLength: 12)

            playbackModeMenu
        }
        .buttonStyle(.plain)
        .font(.title2)
        .padding(.horizontal, 24)
    }

    private var playbackModeMenu: some View {
        Menu {
            ForEach(PlaybackMode.allCases, id: \.rawValue) { mode in
                Button {
                    model.setPlaybackMode(mode)
                } label: {
                    Label(
                        mode.title,
                        systemImage: mode == model.playbackMode ? "checkmark" : mode.symbolName
                    )
                }
            }
        } label: {
            Image(systemName: model.playbackMode.symbolName)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
        }
        .menuIndicator(.hidden)
        .foregroundStyle(model.playbackMode == .order ? .secondary : Color.telistenAccent)
        .accessibilityLabel("Play mode")
        .accessibilityValue(model.playbackMode.title)
    }

    @ViewBuilder
    private var quickActions: some View {
        if let track = model.player.track {
            let vote = model.voteState(for: track)
            HStack(spacing: 12) {
                if !model.isPlaylistTrack(track) {
                    Button {
                        model.upvote(track)
                    } label: {
                        Label(vote.chosen ? "Voted · \(vote.count)" : "Vote up · \(vote.count)", systemImage: vote.chosen ? "hand.thumbsup.fill" : "hand.thumbsup")
                    }
                    .disabled(vote.chosen || vote.isSending)
                }

                Button {
                    model.openPlaylistPicker(for: track)
                } label: {
                    Label("Save to playlist", systemImage: "text.badge.plus")
                }
            }
            .font(.callout.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.telistenAccent)
        }
    }

    private var queue: some View {
        List(Array(model.queue.enumerated()), id: \.element.id) { index, track in
            HStack(spacing: 12) {
                TrackArtwork(model: model, track: track, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.displayTitle).lineLimit(1)
                    Text(track.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if index == model.currentQueueIndex {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.telistenAccent)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.play(track, from: model.queue) }
        }
        .listStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}

private struct CommentsPanel: View {
    @Bindable var model: AppModel
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            comments
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Add a comment", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .submitLabel(.send)
                    .onSubmit(send)

                if model.isSendingComment {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.telistenAccent)
                    .accessibilityLabel("Send comment")
                    .disabled(cleanDraft.isEmpty || model.player.track == nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var comments: some View {
        Group {
            switch model.commentsState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading replies…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case let .loaded(comments) where comments.isEmpty:
                ContentUnavailableView(
                    "No comments yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Replies to this Telegram audio will appear here.")
                )
            case let .loaded(comments):
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(comments) { comment in
                            HStack(alignment: .top, spacing: 12) {
                                Text(initials(for: comment.author))
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.telistenAccent.gradient, in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(comment.author)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(comment.date, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text(comment.text)
                                        .font(.body)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 12)
                            if comment.id != comments.last?.id {
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            case let .failed(message):
                ContentUnavailableView(
                    "Comments unavailable",
                    systemImage: "bubble.left.and.exclamationmark.bubble.right",
                    description: Text(message)
                )
            }
        }
    }

    private var cleanDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        guard let track = model.player.track, !cleanDraft.isEmpty else { return }
        let submitted = cleanDraft
        Task {
            if await model.addComment(submitted, to: track) {
                draft = ""
            }
        }
    }

    private func initials(for author: String) -> String {
        let parts = author.split(separator: " ").prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }
}

private struct LyricsPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.lyricsState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Finding the best lyrics match…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case let .loaded(lyrics):
                lyricsScroll(lyrics)
            case .unavailable:
                ContentUnavailableView(
                    "No lyrics found",
                    systemImage: "quote.bubble",
                    description: Text("This track may be instrumental or missing from LRCLIB.")
                )
            case let .failed(message):
                ContentUnavailableView(
                    "Lyrics unavailable",
                    systemImage: "wifi.exclamationmark",
                    description: Text(message)
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func lyricsScroll(_ lyrics: TrackLyrics) -> some View {
        let activeID = activeLineID(in: lyrics)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: lyrics.isSynced ? 12 : 9) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        let isActive = activeID == line.id
                        let isPast = activeID.flatMap { active in
                            lyrics.lines.firstIndex(where: { $0.id == active })
                        }.map { index < $0 } ?? false
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(lyrics.isSynced ? (isActive ? .title2.bold() : .title3.weight(.semibold)) : .body)
                            .foregroundStyle(isActive || !lyrics.isSynced ? Color.primary : Color.secondary)
                            .opacity(!lyrics.isSynced || isActive ? 1 : (isPast ? 0.36 : 0.64))
                            .scaleEffect(isActive ? 1.02 : 1, anchor: .leading)
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let time = line.time { model.player.seek(to: time) }
                            }
                    }
                    Link("Lyrics by \(lyrics.source)", destination: URL(string: "https://lrclib.net")!)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.telistenAccent)
                        .padding(.top, 12)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.vertical, lyrics.isSynced ? 90 : 0, for: .scrollContent)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onChange(of: activeID, initial: true) { _, lineID in
                guard lyrics.isSynced, let lineID else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo(lineID, anchor: .center)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: activeID)
        }
    }

    private func activeLineID(in lyrics: TrackLyrics) -> Int? {
        guard lyrics.isSynced else { return nil }
        let timedLines = lyrics.lines.filter { $0.time != nil }
        guard let first = timedLines.first else { return nil }
        return timedLines.last(where: { ($0.time ?? .infinity) <= model.player.currentTime })?.id ?? first.id
    }
}
