import CryptoKit
import Foundation
import MTProtoCrypto
import Security

enum SRPProofError: LocalizedError {
    case unsupportedAlgorithm
    case invalidGroup
    case invalidChallenge
    case randomFailure

    var errorDescription: String? {
        switch self {
        case .unsupportedAlgorithm: "This Telegram password algorithm is not supported."
        case .invalidGroup: "Telegram returned an invalid password group."
        case .invalidChallenge: "Telegram returned an invalid password challenge."
        case .randomFailure: "Secure random generation failed."
        }
    }
}

enum TelegramSRP {
    static func proof(password: String, configuration: TL.Account.Password) throws -> TL.InputCheckPasswordSRPType {
        guard let srpID = configuration.srpId,
              let bData = configuration.srpB,
              let current = configuration.currentAlgo else {
            throw SRPProofError.invalidChallenge
        }
        guard case let .passwordKdfAlgoSHA256SHA256PBKDF2HMACSHA512iter100000SHA256ModPow(algo) = current else {
            throw SRPProofError.unsupportedAlgorithm
        }
        guard algo.p.count == SRP.size, algo.g > 1 else { throw SRPProofError.invalidGroup }

        let p = BigUInt(bigEndianBytes: algo.p)
        let g = BigUInt(UInt32(algo.g))
        let b = BigUInt(bigEndianBytes: bData)
        guard b > BigUInt(1), b < p - BigUInt(1), b.bitWidth >= 1_984,
              (p - b).bitWidth >= 1_984 else {
            throw SRPProofError.invalidChallenge
        }

        let aBytes = try randomBytes(count: SRP.size)
        let a = BigUInt(bigEndianBytes: aBytes)
        let aPublic = g.power(a, modulus: p).bigEndianBytes(byteCount: SRP.size)
        guard aPublic.first(where: { $0 != 0 }) != nil else { throw SRPProofError.invalidChallenge }

        let xData = SRP.passwordHash(
            password: Data(password.utf8),
            salt1: algo.salt1,
            salt2: algo.salt2
        )
        let x = BigUInt(bigEndianBytes: xData)
        let gPadded = g.bigEndianBytes(byteCount: SRP.size)
        let k = BigUInt(bigEndianBytes: hash(algo.p + gPadded))
        let u = BigUInt(bigEndianBytes: hash(aPublic + bData))
        guard !u.isZero else { throw SRPProofError.invalidChallenge }

        let gx = g.power(x, modulus: p)
        let kgx = (k * gx) % p
        let base = (b + p - kgx) % p
        let exponent = a + (u * x)
        let shared = base.power(exponent, modulus: p)
        let sessionKey = hash(shared.bigEndianBytes(byteCount: SRP.size))
        let m1 = hash(
            xor(hash(algo.p), hash(gPadded))
                + hash(algo.salt1)
                + hash(algo.salt2)
                + aPublic
                + bData
                + sessionKey
        )
        return .inputCheckPasswordSRP(TL.InputCheckPasswordSRP(srpId: srpID, A: aPublic, M1: m1))
    }

    private static func hash(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func xor(_ lhs: Data, _ rhs: Data) -> Data {
        Data(zip(lhs, rhs).map { $0.0 ^ $0.1 })
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SRPProofError.randomFailure
        }
        return Data(bytes)
    }
}
