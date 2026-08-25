import SwiftUI

struct NowPlayingView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case lyrics = "Lyrics"
        case queue = "Up Next"
        var id: Self { self }
    }

    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .lyrics
    #if os(iOS)
    @Binding var presentationDetent: PresentationDetent
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                hero
                timeline
                controls
                if showsDetails {
                    Picker("Now playing section", selection: $section) {
                        ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 22)

                    Group {
                        switch section {
                        case .lyrics: LyricsPanel(model: model)
                        case .queue: queue
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    mediumLyrics
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .padding(.top, 4)
            .background(Color.telistenBackground)
            #if os(macOS)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    Button("Listen Together", systemImage: "dot.radiowaves.left.and.right") {
                        model.showListenTogetherSheet = true
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(isListeningTogether ? Color.telistenAccent : .primary)
                    if let track = model.player.track {
                        Button("Save to playlist", systemImage: "text.badge.plus") {
                            model.openPlaylistPicker(for: track)
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityHint("Saves this track to a private playlist")
                    }
                    Button("Close") { dismiss() }
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
                .padding(.trailing, 12)
            }
            #endif
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    if let track = model.player.track {
                        Button("Save to playlist", systemImage: "text.badge.plus") {
                            model.openPlaylistPicker(for: track)
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityHint("Saves this track to a private playlist")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Listen Together", systemImage: "dot.radiowaves.left.and.right") {
                        model.showListenTogetherSheet = true
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(isListeningTogether ? Color.telistenAccent : .primary)
                }
                #endif
            }
        }
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(minWidth: 360, minHeight: 620)
        #endif
        .sheet(isPresented: $model.showPlaylistSheet) {
            if let track = model.playlistTrack {
                PlaylistSheet(model: model, track: track)
            }
        }
        .sheet(isPresented: $model.showListenTogetherSheet) {
            ListenTogetherView(model: model)
        }
        .task(id: model.player.track?.id) {
            guard let track = model.player.track else { return }
            await model.loadLyrics(for: track)
        }
    }

    private var isListeningTogether: Bool {
        if case .live = model.listenTogetherState { return true }
        return false
    }

    private var showsDetails: Bool {
        #if os(iOS)
        presentationDetent == .large
        #else
        true
        #endif
    }

    @ViewBuilder
    private var mediumLyrics: some View {
        if let lyricWindow {
            VStack(spacing: 2) {
                ForEach(Array(lyricWindow.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(
                            size: index == 1 ? 23 : 20,
                            weight: index == 1 ? .semibold : .regular
                        ))
                        .foregroundStyle(index == 1 ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.2), value: lyricWindow)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current lyrics")
        }
    }

    private var lyricWindow: [String]? {
        guard let track = model.player.track,
              case let .loaded(lyrics) = model.lyricsState,
              lyrics.trackID == track.id else { return nil }
        let lines = lyrics.lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !lines.isEmpty else { return nil }

        let currentIndex: Int
        if lyrics.isSynced {
            currentIndex = lines.lastIndex(where: {
                guard let time = $0.time else { return false }
                return time <= model.player.currentTime
            }) ?? 0
        } else if model.player.duration > 0 {
            let progress = min(max(model.player.currentTime / model.player.duration, 0), 1)
            currentIndex = min(Int(progress * Double(lines.count)), lines.count - 1)
        } else {
            currentIndex = 0
        }

        return (-1...3).map { offset in
            let index = currentIndex + offset
            return lines.indices.contains(index) ? lines[index].text : " "
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
                    if let listenTogetherSubtitle {
                        Label(listenTogetherSubtitle, systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.telistenAccent)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
    }

    private var listenTogetherSubtitle: String? {
        guard case let .live(session) = model.listenTogetherState else { return nil }
        return "Live in \(session.chat.title)"
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

    private var queue: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.queue.enumerated()), id: \.element.id) { index, track in
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .onTapGesture { model.play(track, from: model.queue) }

                    if index < model.queue.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .scrollIndicators(.hidden)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}

struct DesktopLyricsView: View {
    @Bindable var model: AppModel

    var body: some View {
        LyricsPanel(model: model, style: .desktop)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.telistenBackground)
            .navigationTitle(model.player.track?.displayTitle ?? "Lyrics")
            .task(id: model.player.track?.id) {
                guard let track = model.player.track else { return }
                await model.loadLyrics(for: track)
            }
    }
}

struct LyricsPanel: View {
    enum Style: Equatable {
        case player
        case desktop
    }

    @Bindable var model: AppModel
    var style: Style = .player
    @State private var isShowingMatchChooser = false

    var body: some View {
        Group {
            switch model.lyricsState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Finding lyrics…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case let .loaded(lyrics):
                VStack(spacing: 8) {
                    if model.lyricsCandidates.count > 1 {
                        lyricsChooser(selected: lyrics)
                    }
                    lyricsScroll(lyrics)
                }
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
        .padding(.horizontal, style == .desktop ? 42 : 18)
        .padding(.top, style == .desktop ? 10 : 0)
        .padding(.bottom, style == .desktop ? 0 : 18)
    }

    private func lyricsChooser(selected: TrackLyrics) -> some View {
        Button {
            isShowingMatchChooser = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: selected.isSynced ? "clock" : "text.alignleft")
                    .foregroundStyle(Color.telistenAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidateTitle(selected))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(candidateDetail(selected))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(selectionPosition(selected))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isShowingMatchChooser) {
            lyricsMatchSheet(selected: selected)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
        .accessibilityLabel("Lyrics match")
        .accessibilityValue("\(selected.isSynced ? "Timed" : "Plain"), \(candidateDetail(selected))")
        .accessibilityHint("Choose another lyrics match")
    }

    private func lyricsMatchSheet(selected: TrackLyrics) -> some View {
        NavigationStack {
            List(model.lyricsCandidates, id: \.matchKey) { candidate in
                Button {
                    model.selectLyrics(candidate)
                    isShowingMatchChooser = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: candidate.isSynced ? "clock" : "text.alignleft")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.telistenAccent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidateTitle(candidate))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(candidateDetail(candidate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if candidate.matchKey == selected.matchKey {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.telistenAccent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Lyrics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingMatchChooser = false }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func candidateTitle(_ candidate: TrackLyrics) -> String {
        let title = candidate.matchedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = candidate.matchedArtist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = [title, artist]
            .compactMap { value in value?.isEmpty == false ? value : nil }
            .joined(separator: " — ")
        return identity.isEmpty ? candidate.source : identity
    }

    private func candidateDetail(_ candidate: TrackLyrics) -> String {
        let duration = candidate.matchedDuration.map(DisplayFormat.duration) ?? "Unknown length"
        let edition = candidate.matchedAlbum?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let edition, !edition.isEmpty {
            return "\(duration) · \(edition)"
        }
        let artist = candidate.matchedArtist?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let artist, !artist.isEmpty {
            return "\(duration) · \(artist)"
        }
        return "\(duration) · \(candidate.source)"
    }

    private func selectionPosition(_ selected: TrackLyrics) -> String {
        let index = model.lyricsCandidates.firstIndex(where: { $0.matchKey == selected.matchKey }) ?? 0
        return "\(index + 1)/\(model.lyricsCandidates.count)"
    }

    private func lyricsScroll(_ lyrics: TrackLyrics) -> some View {
        let activeID = activeLineID(in: lyrics)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: style == .desktop ? 22 : (lyrics.isSynced ? 12 : 9)
                ) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        let isActive = activeID == line.id
                        let isPast = activeID.flatMap { active in
                            lyrics.lines.firstIndex(where: { $0.id == active })
                        }.map { index < $0 } ?? false
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(lyricFont(isSynced: lyrics.isSynced, isActive: isActive))
                            .foregroundStyle(isActive || !lyrics.isSynced ? Color.primary : Color.secondary)
                            .opacity(lyricOpacity(isSynced: lyrics.isSynced, isActive: isActive, isPast: isPast))
                            .scaleEffect(isActive ? (style == .desktop ? 1.035 : 1.02) : 1, anchor: .leading)
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
                .padding(style == .desktop ? 28 : 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(
                .vertical,
                style == .desktop ? 150 : (lyrics.isSynced ? 90 : 0),
                for: .scrollContent
            )
            .background(
                Color.primary.opacity(style == .desktop ? 0 : 0.035),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .onChange(of: activeID, initial: true) { _, lineID in
                guard lyrics.isSynced, let lineID else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo(lineID, anchor: .center)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: activeID)
        }
    }

    private func lyricFont(isSynced: Bool, isActive: Bool) -> Font {
        if style == .desktop {
            return .system(size: isActive ? 34 : 27, weight: isActive ? .bold : .semibold)
        }
        return isSynced ? (isActive ? .title2.bold() : .title3.weight(.semibold)) : .body
    }

    private func lyricOpacity(isSynced: Bool, isActive: Bool, isPast: Bool) -> Double {
        guard isSynced, !isActive else { return 1 }
        if style == .desktop { return isPast ? 0.3 : 0.58 }
        return isPast ? 0.36 : 0.64
    }

    private func activeLineID(in lyrics: TrackLyrics) -> Int? {
        guard lyrics.isSynced else { return nil }
        let timedLines = lyrics.lines.filter { $0.time != nil }
        guard let first = timedLines.first else { return nil }
        return timedLines.last(where: { ($0.time ?? .infinity) <= model.player.currentTime })?.id ?? first.id
    }
}
