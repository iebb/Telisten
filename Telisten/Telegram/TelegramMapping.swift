import Foundation

enum TelegramMapping {
    static func chats(from result: TL.Messages.DialogsType) -> [MusicChat] {
        let content: (dialogs: [TL.DialogType], chats: [TL.ChatType], users: [TL.UserType])
        switch result {
        case let .dialogs(value):
            content = (value.dialogs, value.chats, value.users)
        case let .dialogsSlice(value):
            content = (value.dialogs, value.chats, value.users)
        case .dialogsNotModified:
            return []
        }

        var lookup: [String: MusicChat] = [:]
        for item in content.chats {
            if let chat = map(chat: item) { lookup[chat.id] = chat }
        }
        for item in content.users {
            if let chat = map(user: item) { lookup[chat.id] = chat }
        }
        return content.dialogs.compactMap { dialog -> MusicChat? in
            switch dialog {
            case let .dialog(value):
                guard var chat = lookup[key(for: value.peer)] else { return nil }
                chat.isPinned = value.pinned
                return chat
            case .dialogFolder: return nil
            }
        }
    }

    static func tracks(from result: TL.Messages.MessagesType) -> [Track] {
        messages(from: result).compactMap(map(message:))
    }

    static func lyricsAttachments(from result: TL.Messages.MessagesType) -> [TelegramLyricsAttachment] {
        messages(from: result).compactMap(mapLyricsAttachment(message:))
    }

    static func messages(from result: TL.Messages.MessagesType) -> [TL.MessageType] {
        switch result {
        case let .messages(value): value.messages
        case let .messagesSlice(value): value.messages
        case let .channelMessages(value): value.messages
        case .messagesNotModified: []
        }
    }

    static func botSearchMessages(from result: TL.Messages.MessagesType) -> [BotSearchMessage] {
        messages(from: result)
            .compactMap { item -> BotSearchMessage? in
                guard case let .message(message) = item else { return nil }
                let text = message.message.trimmingCharacters(in: .whitespacesAndNewlines)
                let track = map(message: item)
                let rows = botButtonRows(from: message.replyMarkup, messageID: message.id)
                guard !text.isEmpty || track != nil || !rows.isEmpty else { return nil }
                return BotSearchMessage(
                    id: message.id,
                    isOutgoing: message.out,
                    text: text,
                    date: Date(timeIntervalSince1970: TimeInterval(message.date)),
                    buttonRows: rows,
                    track: track
                )
            }
            .sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date < rhs.date
            }
    }

    static func botChat(from result: TL.Contacts.ResolvedPeer) -> MusicChat? {
        guard case let .peerUser(peer) = result.peer,
              case let .user(user)? = result.users.first(where: { value in
                  guard case let .user(value) = value else { return false }
                  return value.id == peer.userId
              }),
              user.bot,
              user.accessHash != nil else { return nil }
        return map(user: .user(user))
    }

    static func messageCount(from result: TL.Messages.MessagesType) -> Int {
        switch result {
        case let .messages(value): Int(value.messages.count)
        case let .messagesSlice(value): Int(value.count)
        case let .channelMessages(value): Int(value.count)
        case let .messagesNotModified(value): Int(value.count)
        }
    }

    static func comments(from result: TL.Messages.MessagesType) -> [TrackComment] {
        let content: (messages: [TL.MessageType], chats: [TL.ChatType], users: [TL.UserType])
        switch result {
        case let .messages(value):
            content = (value.messages, value.chats, value.users)
        case let .messagesSlice(value):
            content = (value.messages, value.chats, value.users)
        case let .channelMessages(value):
            content = (value.messages, value.chats, value.users)
        case .messagesNotModified:
            return []
        }

        var authors: [String: String] = [:]
        for item in content.users {
            guard case let .user(user) = item else { continue }
            let name = [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ")
            authors["u:\(user.id)"] = name.isEmpty ? (user.username ?? "Telegram user") : name
        }
        for item in content.chats {
            switch item {
            case let .chat(chat): authors["g:\(chat.id)"] = chat.title
            case let .chatForbidden(chat): authors["g:\(chat.id)"] = chat.title
            case let .channel(channel): authors["c:\(channel.id)"] = channel.title
            case let .channelForbidden(channel): authors["c:\(channel.id)"] = channel.title
            case .chatEmpty: break
            }
        }

        var seen: Set<String> = []
        return content.messages.compactMap { item -> TrackComment? in
            guard case let .message(message) = item else { return nil }
            let text = message.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let peerKey = key(for: message.peerId)
            let id = "\(peerKey):\(message.id)"
            guard seen.insert(id).inserted else { return nil }
            let authorKey = message.fromId.map(key(for:)) ?? peerKey
            let signature = message.postAuthor?.trimmingCharacters(in: .whitespacesAndNewlines)
            return TrackComment(
                id: id,
                author: signature?.isEmpty == false ? signature! : (authors[authorKey] ?? "Telegram user"),
                text: text,
                date: Date(timeIntervalSince1970: TimeInterval(message.date))
            )
        }
        .sorted { $0.date < $1.date }
    }

    static func chats(from updates: TL.UpdatesType) -> [MusicChat] {
        let values: [TL.ChatType]
        switch updates {
        case let .updates(value): values = value.chats
        case let .updatesCombined(value): values = value.chats
        default: values = []
        }
        return values.compactMap(map(chat:))
    }

    static func contacts(from result: TL.Contacts.ContactsType) -> [MusicChat] {
        guard case let .contacts(value) = result else { return [] }
        let contactIDs = Set(value.contacts.map(\.userId))
        return value.users
            .compactMap(map(user:))
            .filter { contactIDs.contains($0.peerID) && $0.accessHash != nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func chatID(for peer: TL.InputPeerType) -> String? {
        switch peer {
        case let .inputPeerUser(value): "u:\(value.userId)"
        case let .inputPeerChat(value): "g:\(value.chatId)"
        case let .inputPeerChannel(value): "c:\(value.channelId)"
        case let .inputPeerUserFromMessage(value): "u:\(value.userId)"
        case let .inputPeerChannelFromMessage(value): "c:\(value.channelId)"
        case .inputPeerEmpty, .inputPeerSelf: nil
        }
    }

    static func inputPeer(for chat: MusicChat) -> TL.InputPeerType {
        switch chat.kind {
        case .user:
            if let hash = chat.accessHash {
                .inputPeerUser(TL.InputPeerUser(userId: chat.peerID, accessHash: hash))
            } else {
                .inputPeerSelf(TL.InputPeerSelf())
            }
        case .group:
            .inputPeerChat(TL.InputPeerChat(chatId: chat.peerID))
        case .channel:
            .inputPeerChannel(TL.InputPeerChannel(channelId: chat.peerID, accessHash: chat.accessHash ?? 0))
        }
    }

    static func discussionTarget(
        from result: TL.Messages.DiscussionMessage,
        excluding sourceChatID: String
    ) -> (chat: MusicChat, messageID: Int32)? {
        let chats = result.chats.compactMap(map(chat:))
        for item in result.messages {
            let message: (id: Int32, peer: TL.PeerType)? = switch item {
            case let .message(value): (value.id, value.peerId)
            case let .messageService(value): (value.id, value.peerId)
            case .messageEmpty: nil
            }
            guard let message,
                  key(for: message.peer) != sourceChatID,
                  let chat = chats.first(where: { $0.id == key(for: message.peer) }) else { continue }
            return (chat, message.id)
        }
        return nil
    }

    private static func map(chat: TL.ChatType) -> MusicChat? {
        switch chat {
        case let .chat(value):
            makeChat(
                id: "g:\(value.id)", peerID: value.id, accessHash: nil,
                kind: .group, title: value.title, username: nil, photo: value.photo,
                creator: value.creator, adminRights: value.adminRights
            )
        case let .chatForbidden(value):
            MusicChat(id: "g:\(value.id)", peerID: value.id, accessHash: nil, kind: .group, title: value.title, username: nil)
        case let .channel(value):
            makeChat(
                id: "c:\(value.id)", peerID: value.id, accessHash: value.accessHash,
                kind: .channel, title: value.title, username: value.username, photo: value.photo,
                isBroadcast: value.broadcast, creator: value.creator,
                adminRights: value.adminRights
            )
        case let .channelForbidden(value):
            MusicChat(
                id: "c:\(value.id)", peerID: value.id, accessHash: value.accessHash,
                kind: .channel, title: value.title, username: nil, isBroadcast: value.broadcast
            )
        case .chatEmpty:
            nil
        }
    }

    private static func map(user: TL.UserType) -> MusicChat? {
        switch user {
        case let .user(value):
            let name = [value.firstName, value.lastName].compactMap { $0 }.joined(separator: " ")
            let avatar = avatar(from: value.photo)
            return MusicChat(
                id: "u:\(value.id)",
                peerID: value.id,
                accessHash: value.self_ ? nil : value.accessHash,
                kind: .user,
                title: name.isEmpty ? (value.username ?? "User") : name,
                username: value.username,
                avatarPhotoID: avatar?.photoID,
                avatarDCID: avatar?.dcID
            )
        case .userEmpty:
            return nil
        }
    }

    private static func avatar(
        from photo: TL.UserProfilePhotoType?
    ) -> (photoID: Int64, dcID: Int32)? {
        guard let photo else { return nil }
        return switch photo {
        case let .userProfilePhoto(value): (value.photoId, value.dcId)
        case .userProfilePhotoEmpty: nil
        }
    }

    private static func makeChat(
        id: String,
        peerID: Int64,
        accessHash: Int64?,
        kind: PeerKind,
        title: String,
        username: String?,
        photo: TL.ChatPhotoType,
        isBroadcast: Bool? = nil,
        creator: Bool = false,
        adminRights: TL.ChatAdminRights? = nil
    ) -> MusicChat {
        let avatar: (photoID: Int64, dcID: Int32)? = switch photo {
        case let .chatPhoto(value): (value.photoId, value.dcId)
        case .chatPhotoEmpty: nil
        }
        return MusicChat(
            id: id,
            peerID: peerID,
            accessHash: accessHash,
            kind: kind,
            title: title,
            username: username,
            avatarPhotoID: avatar?.photoID,
            avatarDCID: avatar?.dcID,
            isBroadcast: isBroadcast,
            isAdmin: creator || adminRights != nil,
            canInviteUsers: creator || adminRights?.inviteUsers == true,
            canManageCalls: creator || adminRights?.manageCall == true
        )
    }

    private static func key(for peer: TL.PeerType) -> String {
        switch peer {
        case let .peerUser(value): "u:\(value.userId)"
        case let .peerChat(value): "g:\(value.chatId)"
        case let .peerChannel(value): "c:\(value.channelId)"
        }
    }

    private static func map(message item: TL.MessageType) -> Track? {
        guard case let .message(message) = item,
              let media = message.media,
              case let .messageMediaDocument(documentMedia) = media,
              let documentType = documentMedia.document,
              case let .document(document) = documentType else { return nil }

        var audio: TL.DocumentAttributeAudio?
        var isVoice = false
        var fileName = "audio-\(document.id)"
        for attribute in document.attributes {
            switch attribute {
            case let .documentAttributeAudio(value):
                isVoice = value.voice
                audio = value
            case let .documentAttributeFilename(value):
                fileName = value.fileName
            default:
                break
            }
        }
        let isWAV = AudioDocumentFormat.isWAV(fileName: fileName, mimeType: document.mimeType)
        guard !isVoice, audio != nil || isWAV else { return nil }
        if isWAV, (fileName as NSString).pathExtension.isEmpty { fileName += ".wav" }
        let vote = upvote(in: message.reactions)
        let artwork = artworkReference(in: document.thumbs)
        return Track(
            documentID: document.id,
            accessHash: document.accessHash,
            fileReference: document.fileReference,
            dcID: document.dcId,
            messageID: message.id,
            chatID: key(for: message.peerId),
            title: audio?.title ?? fileName.deletingPathExtension,
            artist: audio?.performer ?? "",
            fileName: fileName,
            mimeType: isWAV ? "audio/wav" : document.mimeType,
            duration: TimeInterval(audio?.duration ?? 0),
            size: document.size,
            date: Date(timeIntervalSince1970: TimeInterval(message.date)),
            upvoteCount: vote.count,
            didUpvote: vote.chosen,
            artworkThumbSize: artwork.thumbSize,
            artworkPreview: artwork.preview
        )
    }

    private static func mapLyricsAttachment(message item: TL.MessageType) -> TelegramLyricsAttachment? {
        guard case let .message(message) = item,
              let media = message.media,
              case let .messageMediaDocument(documentMedia) = media,
              let documentType = documentMedia.document,
              case let .document(document) = documentType else { return nil }

        let fileName = document.attributes.compactMap { attribute -> String? in
            guard case let .documentAttributeFilename(value) = attribute else { return nil }
            return value.fileName
        }.first ?? "lyrics-\(document.id).lrc"
        let isLRC = fileName.lowercased().hasSuffix(".lrc")
            || document.mimeType.caseInsensitiveCompare("text/lrc") == .orderedSame
            || document.mimeType.caseInsensitiveCompare("application/lrc") == .orderedSame
        guard isLRC else { return nil }

        return TelegramLyricsAttachment(
            documentID: document.id,
            accessHash: document.accessHash,
            fileReference: document.fileReference,
            dcID: document.dcId,
            messageID: message.id,
            chatID: key(for: message.peerId),
            fileName: fileName,
            mimeType: document.mimeType,
            size: document.size,
            date: Date(timeIntervalSince1970: TimeInterval(message.date))
        )
    }

    private static func artworkReference(in thumbs: [TL.PhotoSizeType]?) -> (thumbSize: String?, preview: Data?) {
        var bestRemote: (type: String, area: Int64)?
        var bestPreview: (data: Data, area: Int64)?

        for thumb in thumbs ?? [] {
            switch thumb {
            case let .photoSize(value):
                let candidate = (value.type, Int64(value.w) * Int64(value.h))
                if candidate.1 > (bestRemote?.area ?? -1) { bestRemote = candidate }
            case let .photoSizeProgressive(value):
                let candidate = (value.type, Int64(value.w) * Int64(value.h))
                if candidate.1 > (bestRemote?.area ?? -1) { bestRemote = candidate }
            case let .photoCachedSize(value):
                let candidate = (value.bytes, Int64(value.w) * Int64(value.h))
                if candidate.1 > (bestPreview?.area ?? -1) { bestPreview = candidate }
            case .photoSizeEmpty, .photoStrippedSize, .photoPathSize:
                break
            }
        }
        return (bestRemote?.type, bestPreview?.data)
    }

    private static func upvote(in reactions: TL.MessageReactions?) -> (count: Int32, chosen: Bool) {
        guard let reaction = reactions?.results.first(where: { item in
            guard case let .reactionEmoji(value) = item.reaction else { return false }
            return value.emoticon == "👍"
        }) else { return (0, false) }
        return (reaction.count, reaction.chosenOrder != nil)
    }

    private static func botButtonRows(
        from markup: TL.ReplyMarkupType?,
        messageID: Int32
    ) -> [[BotSearchButton]] {
        let rows: [TL.KeyboardButtonRow]
        switch markup {
        case let .replyInlineMarkup(value): rows = value.rows
        case let .replyKeyboardMarkup(value): rows = value.rows
        case .replyKeyboardHide, .replyKeyboardForceReply, nil: return []
        }

        return rows.enumerated().map { rowIndex, row in
            row.buttons.enumerated().map { buttonIndex, button in
                let value = botButton(button, messageID: messageID)
                return BotSearchButton(
                    id: "\(messageID):\(rowIndex):\(buttonIndex):\(value.title)",
                    title: value.title,
                    action: value.action
                )
            }
        }
    }

    private static func botButton(
        _ button: TL.KeyboardButtonType,
        messageID: Int32
    ) -> (title: String, action: BotSearchButtonAction) {
        switch button {
        case let .keyboardButton(value):
            return (value.text, .sendText(value.text))
        case let .keyboardButtonCallback(value):
            return (
                value.text,
                value.requiresPassword
                    ? .unsupported
                    : .callback(messageID: messageID, data: value.data)
            )
        case let .keyboardButtonUrl(value):
            return (value.text, URL(string: value.url).map(BotSearchButtonAction.openURL) ?? .unsupported)
        case let .keyboardButtonUrlAuth(value):
            return (value.text, URL(string: value.url).map(BotSearchButtonAction.openURL) ?? .unsupported)
        case let .inputKeyboardButtonUrlAuth(value):
            return (value.text, URL(string: value.url).map(BotSearchButtonAction.openURL) ?? .unsupported)
        case let .keyboardButtonWebView(value):
            return (value.text, URL(string: value.url).map(BotSearchButtonAction.openURL) ?? .unsupported)
        case let .keyboardButtonSimpleWebView(value):
            return (value.text, URL(string: value.url).map(BotSearchButtonAction.openURL) ?? .unsupported)
        case let .keyboardButtonSwitchInline(value):
            return (value.text, .unsupported)
        case let .keyboardButtonGame(value):
            return (value.text, .unsupported)
        case let .keyboardButtonBuy(value):
            return (value.text, .unsupported)
        case let .keyboardButtonRequestPhone(value):
            return (value.text, .unsupported)
        case let .keyboardButtonRequestGeoLocation(value):
            return (value.text, .unsupported)
        case let .keyboardButtonRequestPoll(value):
            return (value.text, .unsupported)
        case let .inputKeyboardButtonUserProfile(value):
            return (value.text, .unsupported)
        case let .keyboardButtonUserProfile(value):
            return (value.text, .unsupported)
        case let .keyboardButtonRequestPeer(value):
            return (value.text, .unsupported)
        case let .inputKeyboardButtonRequestPeer(value):
            return (value.text, .unsupported)
        case let .keyboardButtonCopy(value):
            return (value.text, .unsupported)
        }
    }
}
