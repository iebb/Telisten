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
    var showsCloseButton = false
    #endif
    var isEmbedded = false
    #if os(iOS)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Follows the finger; a cancelled touch (Control Center, a call,
    /// backgrounding) springs the cover back automatically.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.85)))
    private var dragOffset: CGFloat = 0
    /// Holds the released position while a committed dismissal animates away.
    @State private var committedDismissOffset: CGFloat = 0
    @State private var dismissOpacity: Double = 1
    #endif

    /// The iPhone full-screen player (not the iPad pane, Mac or Vision Pro):
    /// swipe-down dismissal, grabber, chevron Close and the new top bar.
    private var isCompactCover: Bool {
        #if os(iOS)
        showsCloseButton && !isEmbedded
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isEmbedded {
                playerContent
            } else {
                NavigationStack { playerContent }
            }
        }
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(CompactCoverChrome(
            isActive: isCompactCover,
            offset: max(dragOffset, committedDismissOffset),
            opacity: dismissOpacity
        ))
        .onAppear {
            committedDismissOffset = 0
            dismissOpacity = 1
        }
        #else
        .frame(minWidth: 360, minHeight: 620)
        #endif
        .sheet(isPresented: isEmbedded ? .constant(false) : $model.showPlaylistSheet) {
            if let track = model.playlistTrack {
                PlaylistSheet(model: model, track: track)
            }
        }
        .sheet(isPresented: isEmbedded ? .constant(false) : $model.showListenTogetherSheet) {
            ListenTogetherView(model: model)
        }
        .task(id: model.player.track?.id) {
            guard let track = model.player.track else { return }
            await model.loadLyrics(for: track)
        }
    }

    private var playerContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 14) {
                VStack(spacing: 14) {
                    Group {
                        if isEmbedded {
                            albumSleeve(artworkSize: min(220, max(80, geometry.size.height * 0.24)))
                        } else {
                            hero
                        }
                    }
                        .frame(maxWidth: 560)
                    timeline
                        .frame(maxWidth: 560)
                    controls
                        .frame(maxWidth: 560)
                    if showsDetails {
                        Picker("Now playing section", selection: $section) {
                            ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .padding(.horizontal, 22)
                    }
                }
                #if os(iOS)
                // Swipe down on the player (not on the lyrics or queue scroll
                // views) to dismiss. Controls and the scrubber keep priority.
                .contentShape(Rectangle())
                .gesture(coverDismissGesture, including: isCompactCover ? .all : .subviews)
                #endif
                if showsDetails {
                    Group {
                        switch section {
                        case .lyrics: LyricsPanel(model: model, style: isEmbedded ? .spread : .player)
                        case .queue: queue
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    mediumLyricRegion
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .padding(.top, 4)
            .background(Color.telistenBackground)
            #if os(macOS)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    OpenLyricsWindowButton()
                        .labelStyle(.iconOnly)
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
                #if os(visionOS)
                ToolbarItemGroup(placement: .primaryAction) {
                    OpenLyricsWindowButton()
                    Button("Listen Together", systemImage: "dot.radiowaves.left.and.right") {
                        model.showListenTogetherSheet = true
                    }
                    if let track = model.player.track {
                        Button("Save to playlist", systemImage: "text.badge.plus") {
                            model.openPlaylistPicker(for: track)
                        }
                    }
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                #endif
                #if os(iOS)
                if isCompactCover {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            model.showNowPlaying = false
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .tint(.primary)
                        .accessibilityLabel("Close Now Playing")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        listenTogetherButton
                        if let track = model.player.track {
                            Button("Save to playlist", systemImage: "text.badge.plus") {
                                model.openPlaylistPicker(for: track)
                            }
                            .labelStyle(.iconOnly)
                            // Neutral like the chevron: red in this bar means Listen Together is live.
                            .tint(.primary)
                            .accessibilityHint("Saves this track to a private playlist")
                        }
                    }
                } else {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if let track = model.player.track {
                            Button("Save to playlist", systemImage: "text.badge.plus") {
                                model.openPlaylistPicker(for: track)
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityHint("Saves this track to a private playlist")
                        }
                        if showsCloseButton {
                            Button("Close", systemImage: "xmark") { model.showNowPlaying = false }
                                .labelStyle(.iconOnly)
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Listen Together", systemImage: "dot.radiowaves.left.and.right") {
                            model.showListenTogetherSheet = true
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(isListeningTogether ? Color.telistenAccent : .primary)
                    }
                }
                #endif
            }
        }
    }

    // A listening spread pairs the browsable collection with an album sleeve.
    // It uses the same player/queue as the compact view, so resizing never reloads audio.
    private func albumSleeve(artworkSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let track = model.player.track {
                ViewThatFits(in: .horizontal) {
                    sleeveArtwork(track, size: artworkSize)
                    sleeveArtwork(track, size: 80)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.displayTitle)
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text(track.displayArtist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func sleeveArtwork(_ track: Track, size: CGFloat) -> some View {
        TrackArtwork(model: model, track: track, size: size)
            .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
    }

    private var isListeningTogether: Bool {
        if case .live = model.listenTogetherState { return true }
        return false
    }

    #if os(iOS)
    /// Off: plain primary glyph. Live: white glyph on a 32 pt accent disc that
    /// animates unless Reduce Motion is on.
    private var listenTogetherButton: some View {
        Button {
            model.showListenTogetherSheet = true
        } label: {
            Group {
                if isListeningTogether {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.telistenAccent))
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityLabel("Listen Together")
        .accessibilityValue(listenTogetherSubtitle ?? localizedUI("Off"))
    }

    private var coverDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($dragOffset) { value, offset, _ in
                // Reduce Motion: the player does not follow the finger.
                offset = reduceMotion ? 0 : max(0, value.translation.height)
            }
            .onEnded { value in
                let distance = value.translation.height
                if distance > 120 || (distance > 0 && value.velocity.height > 800) {
                    if !reduceMotion { committedDismissOffset = max(0, distance) }
                    dismissCover()
                }
                // Otherwise the gesture state springs back to 0 by itself.
            }
    }

    private func dismissCover() {
        guard reduceMotion else {
            model.showNowPlaying = false
            return
        }
        // Reduce Motion: a plain fade instead of the slide-down.
        withAnimation(.easeOut(duration: 0.2)) { dismissOpacity = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.showNowPlaying = false }
        }
    }
    #endif

    private var showsDetails: Bool {
        #if os(iOS)
        presentationDetent == .large
        #else
        true
        #endif
    }

    @ViewBuilder
    private var mediumLyricRegion: some View {
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
        } else {
            mediumLyricStatus
        }
    }

    @ViewBuilder
    private var mediumLyricStatus: some View {
        switch model.lyricsState {
        case .idle, .loading:
            VStack(spacing: 8) {
                ProgressView()
                Text("Finding lyrics…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .unavailable, .loaded:
            Label("No lyrics found", systemImage: "quote.bubble")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        case .failed:
            Label("Lyrics unavailable", systemImage: "wifi.exclamationmark")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
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
        return String(format: localizedUI("Live in %@"), session.chat.title)
    }

    private var timeline: some View {
        PlaybackTimeline(model: model)
    }

    private var controls: some View {
        PlaybackControls(model: model, compact: isEmbedded)
    }

    private var queue: some View {
        PlaybackQueue(model: model)
    }
}

private struct PlaybackQueue: View {
    @Bindable var model: AppModel

    /// iPhone/iPad highlight the playing row like the search list does; Mac and
    /// Vision Pro keep their current row look.
    private var highlightsCurrentRow: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.queue.enumerated()), id: \.element.id) { index, track in
                        let isCurrent = index == model.currentQueueIndex
                        Button {
                            model.play(track, from: model.queue)
                        } label: {
                            HStack(spacing: 12) {
                                TrackArtwork(model: model, track: track, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.displayTitle)
                                        .fontWeight(highlightsCurrentRow && isCurrent ? .semibold : nil)
                                        .foregroundStyle(highlightsCurrentRow && isCurrent ? Color.telistenAccent : Color.primary)
                                        .lineLimit(1)
                                    Text(track.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if isCurrent {
                                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.telistenAccent)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(rowLabel(for: track))
                        .accessibilityValue(isCurrent ? localizedUI("Now playing") : "")
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                        .id(track.id)

                        if index < model.queue.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .scrollIndicators(.hidden)
            .onAppear {
                guard let index = model.currentQueueIndex, model.queue.indices.contains(index) else { return }
                let currentID = model.queue[index].id
                // Let the lazy stack lay out before scrolling to the playing row.
                Task { @MainActor in proxy.scrollTo(currentID, anchor: .center) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func rowLabel(for track: Track) -> String {
        let artist = track.displayArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty ? track.displayTitle : "\(track.displayTitle), \(artist)"
    }
}

private struct PlaybackTimeline: View {
    @Bindable var model: AppModel
    #if os(iOS)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Gesture state, so a cancelled touch restores the scrubber without seeking.
    @GestureState private var scrubFraction: CGFloat?
    #endif

    var body: some View {
        #if os(iOS)
        scrubber
        #else
        sliderTimeline
        #endif
    }

    #if os(iOS)
    /// A touch scrubber in the style of the mini player's bar: no thumb, a 44 pt
    /// hit area, the track grows while dragging, and seeking happens once on release.
    private var scrubber: some View {
        let duration = model.player.duration
        let currentTime = model.player.currentTime
        let canSeek = duration.isFinite && duration > 0
        let isScrubbing = scrubFraction != nil
        let shownTime = scrubFraction.map { TimeInterval($0) * duration } ?? currentTime
        let trackHeight: CGFloat = isScrubbing ? 12 : 6

        return VStack(spacing: 0) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let fraction = scrubFraction
                    ?? (canSeek ? CGFloat(min(max(currentTime / duration, 0), 1)) : 0)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.22))
                    Capsule()
                        .fill(Color.telistenAccent)
                        .frame(width: width * fraction)
                }
                .frame(height: trackHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($scrubFraction) { value, fraction, _ in
                            guard canSeek, width > 0 else { return }
                            fraction = min(max(value.location.x / width, 0), 1)
                        }
                        .onEnded { value in
                            guard canSeek, width > 0 else { return }
                            let fraction = min(max(value.location.x / width, 0), 1)
                            model.player.seek(to: duration * fraction)
                        }
                )
            }
            .frame(height: 44)
            .animation(reduceMotion ? nil : .spring(response: 0.25), value: isScrubbing)
            .sensoryFeedback(.impact(weight: .light), trigger: isScrubbing) { wasScrubbing, scrubbing in
                !wasScrubbing && scrubbing
            }
            .playbackPositionAccessibility(
                currentTime: currentTime,
                duration: duration,
                onSeek: { model.player.seek(to: $0) }
            )

            HStack {
                Text(DisplayFormat.duration(shownTime))
                Spacer()
                Text("−\(DisplayFormat.duration(max(0, duration - shownTime)))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(isScrubbing ? HierarchicalShapeStyle.primary : .secondary)
            // 6 pt below the resting 6 pt track, which is centred in the 44 pt hit area.
            .padding(.top, 6 - (44 - 6) / 2)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 26)
    }
    #endif

    private var sliderTimeline: some View {
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
}

private struct PlaybackControls: View {
    @Bindable var model: AppModel
    var compact = false
    @State private var playPauseTaps = 0

    var body: some View {
        HStack(spacing: 0) {
            Button {
                model.player.toggleMute()
            } label: {
                Image(systemName: model.player.volumeSymbolName)
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(model.player.isMuted ? Color.telistenAccent : .secondary)
            .accessibilityLabel(localizedUI(model.player.isMuted ? "Unmute" : "Mute"))

            Spacer(minLength: compact ? 6 : 12)

            HStack(spacing: compact ? 16 : (usesLargeSkipTargets ? 22 : 30)) {
                skipButton("Previous", systemImage: "backward.fill") { model.previous() }
                if model.player.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(width: 52, height: 52)
                        .accessibilityLabel("Loading track")
                } else {
                    playPauseButton
                }
                skipButton("Next", systemImage: "forward.fill") { model.next() }
            }

            Spacer(minLength: compact ? 6 : 12)

            playbackModeMenu
        }
        .buttonStyle(.plain)
        .font(.title2)
        .padding(.horizontal, compact ? 12 : 24)
    }

    /// iPhone/iPad full player: 56 pt Previous/Next targets with 26 pt glyphs.
    private var usesLargeSkipTargets: Bool {
        #if os(iOS)
        !compact
        #else
        false
        #endif
    }

    @ViewBuilder
    private func skipButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        if usesLargeSkipTargets {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 26))
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(title))
        } else {
            Button(title, systemImage: systemImage, action: action)
                .labelStyle(.iconOnly)
        }
    }

    @ViewBuilder
    private var playPauseButton: some View {
        #if os(iOS)
        Button {
            playPauseTaps += 1
            model.player.toggle()
        } label: {
            Image(systemName: model.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 52))
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(localizedUI(model.player.isPlaying ? "Pause" : "Play"))
        // Only the user's own tap gives feedback, not track ends or remote commands.
        .sensoryFeedback(.impact(weight: .light), trigger: playPauseTaps)
        #else
        Button(
            model.player.isPlaying ? "Pause" : "Play",
            systemImage: model.player.isPlaying ? "pause.circle.fill" : "play.circle.fill"
        ) { model.player.toggle() }
            .labelStyle(.iconOnly)
            .font(.system(size: 52))
        #endif
    }

    private var playbackModeMenu: some View {
        Menu {
            ForEach(PlaybackMode.allCases, id: \.rawValue) { mode in
                Button {
                    model.setPlaybackMode(mode)
                } label: {
                    Label(
                        localizedUI(mode.title),
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
        .accessibilityValue(localizedUI(model.playbackMode.title))
    }

}

#if os(iOS)
/// A tabletop separates content for viewing from controls for touching. Both
/// regions share the existing player; changing the layout never restarts audio.
struct TabletopPlayerView<Collection: View>: View {
    @Bindable var model: AppModel
    let upperRegionHeight: CGFloat
    @ViewBuilder var collection: () -> Collection
    @State private var showsQueue = false

    var body: some View {
        VStack(spacing: 0) {
            stage
                .frame(height: max(0, upperRegionHeight - 16))
                .clipped()

            // Leave the screen midpoint free of text, sliders and tap targets.
            Color.clear.frame(height: 32).accessibilityHidden(true)

            VStack(spacing: 8) {
                PlaybackTimeline(model: model)
                    .frame(maxWidth: 580)
                PlaybackControls(model: model)
                    .frame(maxWidth: 480)
            }
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)

            Divider().padding(.horizontal, 24)
            Group {
                if showsQueue {
                    NavigationStack {
                        PlaybackQueue(model: model)
                            .navigationTitle("Up Next")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Browse", systemImage: "chevron.left") { showsQueue = false }
                                }
                            }
                    }
                } else {
                    collection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Color.telistenBackground)
        .task(id: model.player.track?.id) {
            guard let track = model.player.track else { return }
            await model.loadLyrics(for: track)
        }
    }

    private var stage: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                HStack {
                    Button("Listen Together", systemImage: "dot.radiowaves.left.and.right") {
                        model.showListenTogetherSheet = true
                    }
                    Spacer()
                    Button(showsQueue ? "Browse music" : "Up Next", systemImage: "list.bullet") {
                        showsQueue.toggle()
                    }
                    .accessibilityValue(showsQueue ? "Shown" : "Hidden")
                    if let track = model.player.track {
                        Button("Save to playlist", systemImage: "text.badge.plus") {
                            model.openPlaylistPicker(for: track)
                        }
                    }
                    Button("Close", systemImage: "xmark") { model.showNowPlaying = false }
                        .accessibilityIdentifier("tabletop.close")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(TabletopActionStyle())

                HStack(spacing: 20) {
                    if let track = model.player.track {
                        VStack(alignment: .leading, spacing: 12) {
                            if geometry.size.height >= 240 {
                                TrackArtwork(
                                    model: model, track: track,
                                    size: min(180, max(72, geometry.size.height - 158))
                                )
                                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.displayTitle)
                                    .font(.title2.bold())
                                    .lineLimit(2)
                                Text(track.displayArtist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if case let .live(session) = model.listenTogetherState {
                                    Text("Live in \(session.chat.title)")
                                        .font(.caption)
                                        .foregroundStyle(Color.telistenAccent)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(width: min(230, geometry.size.width * 0.34), alignment: .leading)
                    }
                    LyricsPanel(model: model, style: .tabletop)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }
}

/// Chrome for the iPhone full-screen player: an opaque surface that can follow
/// a downward drag (revealing the library behind it) and a grabber.
private struct CompactCoverChrome: ViewModifier {
    let isActive: Bool
    let offset: CGFloat
    let opacity: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 36, height: 5)
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
                .offset(y: offset)
                .opacity(opacity)
        } else {
            content
        }
    }
}

private struct TabletopActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color.telistenAccent)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
#endif

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
        case spread
        case tabletop
        case desktop
    }

    @Bindable var model: AppModel
    var style: Style = .player
    @State private var isShowingMatchChooser = false
    /// Auto-follow of the active line. A user scroll pauses it (iPhone/iPad
    /// player panel only) until "Back to Now" or 4 s without a touch.
    @State private var isFollowing = true
    @State private var resumeFollowTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pausesFollowWhileReading: Bool {
        #if os(iOS)
        style == .player
        #else
        false
        #endif
    }

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
                    description: Text(localizedUI(message))
                )
            }
        }
        // A new track always starts following again, and a pending resume
        // never outlives the panel.
        .onChange(of: model.player.track?.id) { _, _ in resumeFollowing() }
        .onDisappear {
            resumeFollowTask?.cancel()
            resumeFollowTask = nil
        }
        .padding(.horizontal, style == .desktop ? 42 : (style == .tabletop ? 0 : 18))
        .padding(.top, style == .desktop ? 10 : 0)
        .padding(.bottom, style == .desktop || style == .tabletop ? 0 : 18)
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
                        lyricLine(line)
                            .font(lyricFont(isSynced: lyrics.isSynced, isActive: isActive))
                            .foregroundStyle(isActive || !lyrics.isSynced ? Color.primary : Color.secondary)
                            .opacity(lyricOpacity(isSynced: lyrics.isSynced, isActive: isActive, isPast: isPast))
                            .scaleEffect(isActive ? (style == .desktop ? 1.035 : 1.02) : 1, anchor: .leading)
                            .id(line.id)
                    }
                    Link("Lyrics by \(lyrics.source)", destination: model.lyricsServerURL)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.telistenAccent)
                        .padding(.top, 12)
                }
                .padding(style == .desktop ? 28 : (style == .tabletop ? 12 : 20))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(
                .vertical,
                style == .desktop ? 150 : (lyrics.isSynced ? (style == .player ? 90 : 40) : 0),
                for: .scrollContent
            )
            .background(
                Color.primary.opacity(style == .player ? 0.035 : 0),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .onChange(of: activeID, initial: true) { _, lineID in
                guard lyrics.isSynced, isFollowing, let lineID else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo(lineID, anchor: .center)
                }
            }
            .onChange(of: isFollowing) { _, following in
                guard following, lyrics.isSynced, let activeID else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                    proxy.scrollTo(activeID, anchor: .center)
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                guard pausesFollowWhileReading, lyrics.isSynced else { return }
                if newPhase == .interacting {
                    // Any user scroll pauses auto-follow.
                    resumeFollowTask?.cancel()
                    resumeFollowTask = nil
                    isFollowing = false
                } else if oldPhase == .interacting, !isFollowing {
                    scheduleFollowResume()
                }
            }
            .overlay(alignment: .bottom) {
                if pausesFollowWhileReading, !isFollowing {
                    backToNowButton
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isFollowing)
            .animation(.easeInOut(duration: 0.22), value: activeID)
        }
    }

    private var backToNowButton: some View {
        Button {
            resumeFollowing()
        } label: {
            Label("Back to Now", systemImage: "arrow.down.to.line")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(.regularMaterial, in: Capsule())
                // The material alone has almost no edge on the light grey panel.
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                // 36 pt capsule, 44 pt touch target.
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The capsule's bottom sits 12 pt above the panel's bottom edge.
        .padding(.bottom, 12 - 4)
    }

    private func scheduleFollowResume() {
        resumeFollowTask?.cancel()
        resumeFollowTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            isFollowing = true
            resumeFollowTask = nil
        }
    }

    private func resumeFollowing() {
        resumeFollowTask?.cancel()
        resumeFollowTask = nil
        isFollowing = true
    }

    @ViewBuilder
    private func lyricLine(_ line: LyricLine) -> some View {
        if let time = line.time {
            Button {
                model.player.seek(to: time)
            } label: {
                Text(line.text.isEmpty ? " " : line.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Seek to \(DisplayFormat.duration(time))")
            #if os(visionOS)
            .hoverEffect(.highlight)
            #endif
        } else {
            Text(line.text.isEmpty ? " " : line.text)
        }
    }

    private func lyricFont(isSynced: Bool, isActive: Bool) -> Font {
        if style == .desktop {
            return .system(size: isActive ? 34 : 27, weight: isActive ? .bold : .semibold)
        }
        if style == .tabletop {
            return .system(size: isActive ? 28 : 22, weight: isActive ? .bold : .medium)
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
