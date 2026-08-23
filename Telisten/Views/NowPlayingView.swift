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
            VStack(spacing: 18) {
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
            .padding(.top, 12)
            .background(Color.telistenBackground)
            .navigationTitle("Now Playing")
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
        HStack(spacing: 18) {
            if let track = model.player.track {
                TrackArtwork(model: model, track: track, size: 108, fallbackSymbol: "waveform")
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
                VStack(alignment: .leading, spacing: 7) {
                    Text(track.displayTitle)
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text(track.displayArtist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Label("Telegram audio", systemImage: "paperplane.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.telistenAccent)
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
        HStack(spacing: 30) {
            Button("Shuffle", systemImage: "shuffle") { model.shuffle.toggle() }
                .foregroundStyle(model.shuffle ? Color.telistenAccent : .secondary)
            Button("Previous", systemImage: "backward.fill") { model.previous() }
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
                    .font(.system(size: 52))
            }
            Button("Next", systemImage: "forward.fill") { model.next() }
            Button("Repeat", systemImage: model.repeatMode.symbolName) { model.cycleRepeat() }
                .foregroundStyle(model.repeatMode == .off ? .secondary : Color.telistenAccent)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .font(.title2)
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

    var body: some View {
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
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func initials(for author: String) -> String {
        let parts = author.split(separator: " ").prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }
}

private struct LyricsPanel: View {
    @Bindable var model: AppModel
    @State private var activeID: Int?

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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: lyrics.isSynced ? 15 : 10) {
                    ForEach(lyrics.lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(lyrics.isSynced ? .title3.weight(activeID == line.id ? .bold : .semibold) : .body)
                            .foregroundStyle(activeID == line.id || !lyrics.isSynced ? .primary : .secondary)
                            .opacity(activeID == line.id || !lyrics.isSynced ? 1 : 0.58)
                            .scaleEffect(activeID == line.id ? 1.015 : 1, anchor: .leading)
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
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onAppear { updateActiveLine(lyrics, proxy: proxy, animated: false) }
            .onChange(of: model.player.currentTime) { _, _ in
                updateActiveLine(lyrics, proxy: proxy, animated: true)
            }
        }
    }

    private func updateActiveLine(_ lyrics: TrackLyrics, proxy: ScrollViewProxy, animated: Bool) {
        guard lyrics.isSynced,
              let line = lyrics.lines.last(where: { ($0.time ?? .infinity) <= model.player.currentTime }),
              line.id != activeID else { return }
        activeID = line.id
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(line.id, anchor: .center) }
        } else {
            proxy.scrollTo(line.id, anchor: .center)
        }
    }
}
