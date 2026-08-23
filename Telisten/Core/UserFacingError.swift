import Foundation
import MTProtoClientKit

enum UserFacingError {
    static func isExpiredTelegramSession(_ error: Error) -> Bool {
        if let rpc = error as? MTProtoRPCError {
            return [
                "AUTH_KEY_UNREGISTERED",
                "SESSION_REVOKED",
                "SESSION_EXPIRED",
                "AUTH_KEY_DUPLICATED"
            ].contains(rpc.message)
        }
        if let client = error as? MTProtoClientError,
           case let .protocolError(code) = client {
            return code == -404
        }
        return false
    }

    static func message(for error: Error) -> String {
        if let rpc = error as? MTProtoRPCError {
            switch rpc.message {
            case "AUTH_KEY_UNREGISTERED", "SESSION_REVOKED", "SESSION_EXPIRED":
                return "Your Telegram session expired. Sign in again to continue."
            case "AUTH_KEY_DUPLICATED":
                return "Telegram invalidated this duplicated session. Sign in again to create a fresh one."
            case "FILE_REFERENCE_EXPIRED", "FILE_REFERENCE_INVALID":
                return "This track reference expired. Refresh the music list and try again."
            default:
                return "Telegram error: \(rpc.message)"
            }
        }
        if let client = error as? MTProtoClientError {
            switch client {
            case .notConnected, .connectionClosed:
                return "The Telegram connection closed. Try again."
            case .timeout:
                return "Telegram did not respond in time. Check your connection and try again."
            case let .protocolError(code):
                return "Telegram rejected the connection (protocol \(code)). Try again."
            case .fatalBadMessage:
                return "Telegram rejected the encrypted session. Sign in again and retry."
            }
        }
        return error.localizedDescription
    }
}
