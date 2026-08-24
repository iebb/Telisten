import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Color {
    static let telistenAccent = Color(red: 0.96, green: 0.30, blue: 0.24)
    static let telistenBackground = Color.primary.opacity(0.035)
}

struct ArtworkTile: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.telistenAccent, Color(red: 0.54, green: 0.16, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct TrackArtwork: View {
    let model: AppModel
    let track: Track
    let size: CGFloat
    var fallbackSymbol = "music.note"

    var body: some View {
        Group {
            if let image = platformImage {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ArtworkTile(symbol: fallbackSymbol, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .task(id: track.id) {
            await model.loadArtwork(for: track)
        }
    }

    private var platformImage: Image? {
        guard let data = model.artworkData[track.id] else { return nil }
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}

struct ChatAvatar: View {
    let model: AppModel
    let chat: MusicChat
    let size: CGFloat
    var fallbackSymbol: String? = nil

    var body: some View {
        Group {
            if let image = platformImage {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay {
                        Image(systemName: fallbackSymbol ?? chat.symbolName)
                            .font(.system(size: size * 0.4, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .task(id: "\(chat.id):\(chat.avatarPhotoID ?? 0)") {
            await model.loadAvatar(for: chat)
        }
    }

    private var platformImage: Image? {
        guard let data = model.chatAvatarData[chat.id] else { return nil }
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}

struct AccountAvatar: View {
    let model: AppModel
    let account: TelegramAccount
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image = platformImage {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Circle()
                    .fill(Color.telistenAccent.opacity(0.12))
                    .overlay {
                        Text(account.initial)
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundStyle(Color.telistenAccent)
                    }
            }
        }
        .frame(width: size, height: size)
        .fixedSize()
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .task(id: "\(account.id):\(account.avatarPhotoID ?? 0)") {
            await model.loadAvatar(for: account)
        }
    }

    private var platformImage: Image? {
        guard let data = model.accountAvatarData[account.id] else { return nil }
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(22)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }
}

extension View {
    func telistenCard() -> some View { modifier(CardModifier()) }
}
