import SwiftUI

struct PlayerBar: View {
    @Bindable var model: AppModel
    var bottomSafeArea: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: model.player.currentTime, total: max(model.player.duration, 1))
                .progressViewStyle(.linear)
                .tint(.telistenAccent)
            HStack(spacing: 10) {
                if let track = model.player.track {
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
                HStack(spacing: 13) {
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
                    Button("Now Playing", systemImage: "list.bullet") { model.showNowPlaying = true }
                        .labelStyle(.iconOnly)
                }
                .font(.callout)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
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
