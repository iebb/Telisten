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

/// Launch arguments used by debug/demo switches such as `--demo`.
///
/// Release builds read only the process arguments. Debug builds additionally
/// accept the whitespace-separated value of `TELISTEN_DEMO_ARGS`, so tools that
/// can set environment variables but not arguments (for example a remote
/// Simulator launcher) can start demo mode: `TELISTEN_DEMO_ARGS="--demo --demo-chat"`.
enum LaunchArguments {
    static let environmentKey = "TELISTEN_DEMO_ARGS"

    static var all: [String] {
        resolved(
            processArguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func contains(_ argument: String) -> Bool {
        all.contains(argument)
    }

    static func resolved(processArguments: [String], environment: [String: String]) -> [String] {
        #if DEBUG
        guard let extra = environment[environmentKey] else { return processArguments }
        return processArguments + extra.split(whereSeparator: \.isWhitespace).map(String.init)
        #else
        return processArguments
        #endif
    }
}
