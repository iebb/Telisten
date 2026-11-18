import SwiftUI

struct PlayerBar: View {
    @Bindable var model: AppModel
    #if os(macOS)
    @Binding var showsLyrics: Bool
    #endif
    var bottomSafeArea: CGFloat = 0
    var usesWideLayout = false
    @State private var playPauseTaps = 0

    /// iPhone (compact width) gets a simplified bar: larger type, only
    /// Play/Pause and Next with 44 pt targets, and a display-only progress bar.
    /// The iPad wide bar, macOS and visionOS keep the full control set.
    private var usesCompactPhoneLayout: Bool {
        #if os(iOS)
        !usesWideLayout
        #else
        false
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            CompactSeekBar(
                currentTime: model.player.currentTime,
                duration: model.player.duration,
                onSeek: model.player.seek,
                allowsDragging: !usesCompactPhoneLayout
            )
            HStack(spacing: 10) {
                if let track = model.player.track {
                    Button {
                        model.showNowPlaying = true
                    } label: {
                        HStack(spacing: 10) {
                            TrackArtwork(model: model, track: track, size: usesCompactPhoneLayout ? 44 : 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.displayTitle)
                                    .font(usesCompactPhoneLayout ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(track.displayArtist)
                                    .font(usesCompactPhoneLayout ? .footnote : .caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Show Now Playing: \(track.displayTitle) by \(track.displayArtist)")
                    .frame(maxWidth: usesWideLayout ? 240 : .infinity, alignment: .leading)
                }
                if usesWideLayout {
                    Group {
                        if let lyricPreview {
                            Button { model.showNowPlaying = true } label: {
                                VStack(spacing: 3) {
                                    Text(lyricPreview[0]).font(.callout.weight(.semibold))
                                    Text(lyricPreview[1]).font(.footnote).foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Show lyrics")
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                if usesCompactPhoneLayout {
                    compactPhoneControls
                } else {
                    HStack(spacing: 13) {
                        #if os(macOS)
                        Button(showsLyrics ? "Hide Lyrics" : "Lyrics", systemImage: "quote.bubble") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showsLyrics.toggle()
                            }
                        }
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(showsLyrics ? Color.telistenAccent : Color.secondary)
                        .accessibilityValue(showsLyrics ? "Shown" : "Hidden")
                        .keyboardShortcut("l", modifiers: .command)
                        #endif
                        #if os(macOS) || os(visionOS)
                        OpenLyricsWindowButton()
                            .labelStyle(.iconOnly)
                        #endif
                        Button("Previous", systemImage: "backward.fill") { model.previous() }
                            .labelStyle(.iconOnly)
                        if model.player.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 28, height: 28)
                                .accessibilityLabel("Loading \(model.player.track?.displayTitle ?? "track")")
                        } else {
                            Button(model.player.isPlaying ? "Pause" : "Play", systemImage: model.player.isPlaying ? "pause.circle.fill" : "play.circle.fill") {
                                model.player.toggle()
                            }
                            .labelStyle(.iconOnly)
                            .font(.system(size: 28))
                        }
                        Button("Next", systemImage: "forward.fill") { model.next() }
                            .labelStyle(.iconOnly)
                        Button(localizedUI(model.playbackMode.title), systemImage: model.playbackMode.symbolName) {
                            model.cyclePlaybackMode()
                        }
                            .labelStyle(.iconOnly)
                            .contentTransition(.symbolEffect(.replace))
                            .accessibilityValue(localizedUI(model.playbackMode.title))
                            .accessibilityHint("Switches to \(localizedUI(model.playbackMode.next.title).lowercased())")
                    }
                    .font(.callout)
                }
            }
            #if os(visionOS)
            .buttonStyle(.borderless)
            .controlSize(.large)
            #else
            .buttonStyle(.plain)
            #endif
            .padding(.horizontal, 12)
            .padding(.vertical, usesCompactPhoneLayout ? 3 : 7)
            // The control row always wins over the lyric strip below it.
            .zIndex(1)
        }
        // Drawn behind the bar so it can never take a touch from the controls.
        // Its top edge sits at the bar's bottom edge, inside the safe area.
        .background(alignment: .bottom) {
            if let lyricPreview, bottomSafeArea > 0, !usesWideLayout {
                VStack(alignment: .center, spacing: 0) {
                    ForEach(Array(lyricPreview.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: index == 0 ? 13.4 : 11.5, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.center)
                    }
                }
                // The tappable area is only the visible text box.
                .contentShape(Rectangle())
                .onTapGesture { model.showNowPlaying = true }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Lyrics preview")
                .accessibilityAddTraits(.isButton)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
                // A zero-height anchor on the bar's bottom edge; the strip hangs
                // below it, so its top edge is exactly the bar's bottom edge.
                .frame(height: 0, alignment: .top)
            }
        }
        // A single surface covers both controls and safe-area lyrics. Separate
        // materials sample different backgrounds and create a seam in dark mode.
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .padding(.bottom, -bottomSafeArea)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var compactPhoneControls: some View {
        HStack(spacing: 4) {
            Group {
                if model.player.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading \(model.player.track?.displayTitle ?? "track")")
                } else {
                    Button {
                        playPauseTaps += 1
                        model.player.toggle()
                    } label: {
                        Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(localizedUI(model.player.isPlaying ? "Pause" : "Play"))
                    #if os(iOS)
                    .sensoryFeedback(.impact(weight: .light), trigger: playPauseTaps)
                    #endif
                }
            }
            .frame(width: 44, height: 44)
            Button {
                model.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Next")
        }
        .foregroundStyle(.primary)
    }

    private var lyricPreview: [String]? {
        guard let track = model.player.track,
              case let .loaded(lyrics) = model.lyricsState,
              lyrics.trackID == track.id else { return nil }
        let lines = lyrics.lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !lines.isEmpty else { return nil }

        let index: Int
        if lyrics.isSynced {
            index = lines.lastIndex(where: {
                guard let time = $0.time else { return false }
                return time <= model.player.currentTime
            }) ?? 0
        } else if model.player.duration > 0 {
            let progress = min(max(model.player.currentTime / model.player.duration, 0), 1)
            index = min(Int(progress * Double(lines.count)), lines.count - 1)
        } else {
            index = 0
        }

        return (0..<2).map { offset in
            let lineIndex = index + offset
            return lines.indices.contains(lineIndex) ? lines[lineIndex].text : " "
        }
    }
}

private struct CompactSeekBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    /// The iPhone mini player shows progress only; seeking happens in Now Playing.
    var allowsDragging = true

    @State private var scrubFraction: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = scrubFraction ?? playbackFraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(height: 3)

                Capsule()
                    .fill(Color.telistenAccent)
                    .frame(width: width * fraction, height: 3)

                if scrubFraction != nil {
                    Circle()
                        .fill(Color.telistenAccent)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                        .offset(x: min(max(width * fraction - 5, 0), max(width - 10, 0)))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canSeek, width > 0 else { return }
                        scrubFraction = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { value in
                        guard canSeek, width > 0 else {
                            scrubFraction = nil
                            return
                        }
                        let fraction = min(max(value.location.x / width, 0), 1)
                        onSeek(duration * fraction)
                        scrubFraction = nil
                    },
                including: allowsDragging ? .all : .none
            )
        }
        .frame(height: 3)
        .playbackPositionAccessibility(currentTime: currentTime, duration: duration, onSeek: onSeek)
    }

    private var canSeek: Bool {
        duration.isFinite && duration > 0
    }

    private var playbackFraction: CGFloat {
        guard canSeek else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
}
