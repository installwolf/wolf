import Foundation
import CryptoKit

/// One encrypted accountability event, safe to hand to an untrusted relay.
/// A fresh ephemeral key per event gives forward secrecy; `sealedB64` is the
/// ChaChaPoly combined box (nonce + ciphertext + tag). Only the holder of the
/// partner private key matching the enrollment public key can open it.
public struct SealedEvent: Codable, Equatable {
    public var ts: Date
    public var ephemeralPublicKeyB64: String
    public var sealedB64: String
}

/// Sealed-box crypto for accountability events. X25519 ECDH → HKDF-SHA256 →
/// ChaChaPoly. CryptoKit only — no external dependency, so it stays in the
/// audited open-source core. The relay never sees plaintext.
public enum SealedBox {
    private static let info = Data("wolf-accountability-v1".utf8)

    private static func decodeKey(_ b64: String) throws -> Curve25519.KeyAgreement.PublicKey {
        guard let raw = Data(base64Encoded: b64) else {
            throw WolfError.crypto("bad recipient public key encoding")
        }
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw)
    }

    /// Derive the per-message symmetric key. Salt is the ephemeral public key,
    /// which travels with the message so the recipient derives the same key.
    private static func symmetricKey(_ shared: SharedSecret,
                                     ephemeralPublicKey: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self,
                                       salt: ephemeralPublicKey,
                                       sharedInfo: info,
                                       outputByteCount: 32)
    }

    public static func seal(_ plaintext: Data, to recipientPublicKeyB64: String,
                            at now: Date) throws -> SealedEvent {
        let recipient = try decodeKey(recipientPublicKeyB64)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPub = ephemeral.publicKey.rawRepresentation
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let key = symmetricKey(shared, ephemeralPublicKey: ephemeralPub)
        let box = try ChaChaPoly.seal(plaintext, using: key)
        return SealedEvent(ts: now,
                           ephemeralPublicKeyB64: ephemeralPub.base64EncodedString(),
                           sealedB64: box.combined.base64EncodedString())
    }

    /// Open with the partner private key (partner-side / tests). The daemon only
    /// ever seals — it never holds a private key that can read the outbox.
    public static func open(_ event: SealedEvent,
                            withRecipientPrivateKey recipient: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        guard let ephRaw = Data(base64Encoded: event.ephemeralPublicKeyB64),
              let combined = Data(base64Encoded: event.sealedB64) else {
            throw WolfError.crypto("bad sealed-event encoding")
        }
        let ephemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephRaw)
        let shared = try recipient.sharedSecretFromKeyAgreement(with: ephemeral)
        let key = symmetricKey(shared, ephemeralPublicKey: ephRaw)
        return try ChaChaPoly.open(try ChaChaPoly.SealedBox(combined: combined), using: key)
    }
}

/// Append-only outbox of sealed accountability events, mirroring `Audit`'s
/// tamper-evident design (`sappnd`: entries can be added, not quietly erased).
/// The daemon's delivery worker (Phase 2) drains this to the relay. Because
/// events are sealed to the partner's key, the outbox on disk — like the relay —
/// reveals nothing without the partner's private key.
public enum Notifier {
    public static var path: String { Paths.home + "/outbox.jsonl" }

    /// Seal `event` to the partner and append it. Best-effort and non-throwing so
    /// notification can never block or fail a gate mutation.
    public static func enqueue(_ event: String, to partner: PartnerChannel,
                               at date: Date = Date()) {
        guard let sealed = try? SealedBox.seal(Data(event.utf8),
                                               to: partner.publicKeyB64, at: date),
              let line = try? JSONEncoder().encode(sealed) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Paths.home, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
        if let h = FileHandle(forWritingAtPath: path) {
            defer { try? h.close() }
            h.seekToEndOfFile()
            h.write(line)
            h.write(Data("\n".utf8))
        }
        Shell.run("/usr/bin/chflags", ["sappnd", path])
    }
}
