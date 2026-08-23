import Foundation

enum AppConfigurationError: LocalizedError {
    case missingTelegramCredentials

    var errorDescription: String? {
        "Telegram credentials are missing. Add them to .env and run Scripts/generate-local-config.sh."
    }
}

extension TelegramCredentials {
    static func appCredentials(in bundle: Bundle = .main) throws -> TelegramCredentials {
        let rawID = bundle.object(forInfoDictionaryKey: "TelegramAPIID")
        let id: Int32?
        if let number = rawID as? NSNumber {
            id = number.int32Value
        } else if let text = rawID as? String {
            id = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            id = nil
        }

        let hash = (bundle.object(forInfoDictionaryKey: "TelegramAPIHash") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let id, id > 0, hash.count == 32, !hash.contains("$(") else {
            throw AppConfigurationError.missingTelegramCredentials
        }
        return TelegramCredentials(apiID: id, apiHash: hash)
    }
}
