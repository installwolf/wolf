import Foundation
import CommonCrypto

/// A salted PBKDF2-HMAC-SHA256 hash of the partner passphrase. We store only
/// the hash + salt, never the passphrase — so the person setting it (the
/// accountability partner) can hold a secret the addicted user never learns.
public struct PassphraseHash: Codable, Equatable {
    public var saltB64: String
    public var hashB64: String
    public var iterations: Int
}

public enum Passphrase {
    public static func make(_ passphrase: String, iterations: Int = 200_000) throws -> PassphraseHash {
        var salt = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt) == errSecSuccess else {
            throw BulwarkError.crypto("failed to generate salt")
        }
        let hash = try derive(passphrase, salt: salt, iterations: iterations)
        return PassphraseHash(saltB64: Data(salt).base64EncodedString(),
                              hashB64: Data(hash).base64EncodedString(),
                              iterations: iterations)
    }

    public static func verify(_ passphrase: String, against stored: PassphraseHash) -> Bool {
        guard let salt = Data(base64Encoded: stored.saltB64),
              let expected = Data(base64Encoded: stored.hashB64),
              let got = try? derive(passphrase, salt: [UInt8](salt), iterations: stored.iterations)
        else { return false }
        // Constant-time compare.
        guard got.count == expected.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(got, [UInt8](expected)) { diff |= a ^ b }
        return diff == 0
    }

    private static func derive(_ passphrase: String, salt: [UInt8], iterations: Int) throws -> [UInt8] {
        let pw = Array(passphrase.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            pw.map { Int8(bitPattern: $0) }, pw.count,
            salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(iterations),
            &out, out.count
        )
        guard status == kCCSuccess else { throw BulwarkError.crypto("PBKDF2 failed (\(status))") }
        return out
    }
}
