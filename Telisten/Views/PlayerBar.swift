import SwiftUI

struct PlayerBar: View {
    @Bindable var model: AppModel
    #if os(macOS)
    @Binding var showsLyrics: Bool
    #endif
    var bottomSafeArea: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            CompactSeekBar(
                currentTime: model.player.currentTime,
                duration: model.player.duration,
                onSeek: model.player.seek
            )
            HStack(spacing: 10) {
                if let track = model.player.track {
                    Button {
                        model.showNowPlaying = true
                    } label: {
                        HStack(spacing: 10) {
                            TrackArtwork(model: model, track: track, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.displayTitle)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(track.displayArtist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Show Now Playing: \(track.displayTitle) by \(track.displayArtist)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                    Button(model.playbackMode.title, systemImage: model.playbackMode.symbolName) {
                        model.cyclePlaybackMode()
                    }
                        .labelStyle(.iconOnly)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityValue(model.playbackMode.title)
                        .accessibilityHint("Switches to \(model.playbackMode.next.title.lowercased())")
                }
                .font(.callout)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            if let lyricPreview, bottomSafeArea > 0 {
                VStack(alignment: .center, spacing: 0) {
                    ForEach(Array(lyricPreview.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: index == 0 ? 13.4 : 11.5, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: bottomSafeArea, alignment: .center)
                .background(.regularMaterial)
                .offset(y: max(bottomSafeArea - 6, 0))
                .contentShape(Rectangle())
                .onTapGesture { model.showNowPlaying = true }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Lyrics preview")
            }
        }
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
                    }
            )
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(DisplayFormat.duration(currentTime)) of \(DisplayFormat.duration(duration))")
        .accessibilityAdjustableAction { direction in
            guard canSeek else { return }
            let step = max(duration * 0.05, 10)
            switch direction {
            case .increment:
                onSeek(min(currentTime + step, duration))
            case .decrement:
                onSeek(max(currentTime - step, 0))
            @unknown default:
                break
            }
        }
    }

    private var canSeek: Bool {
        duration.isFinite && duration > 0
    }

    private var playbackFraction: CGFloat {
        guard canSeek else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
}
