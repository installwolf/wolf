import XCTest
import CryptoKit
@testable import WolfCore

/// Slice 2 of the accountability partner (docs/accountability-partner.md):
/// events are sealed to the partner's X25519 public key and appended to a
/// root-owned, append-only outbox. Only the partner's private key can open them.
final class SealedBoxTests: XCTestCase {
    func testSealOpenRoundTrip() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let pub = recipient.publicKey.rawRepresentation.base64EncodedString()
        let msg = Data("remove queued: pornhub.com".utf8)
        let sealed = try SealedBox.seal(msg, to: pub, at: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(sealed.ts, Date(timeIntervalSince1970: 1_000_000))
        let opened = try SealedBox.open(sealed, withRecipientPrivateKey: recipient)
        XCTAssertEqual(opened, msg)
    }

    func testWrongKeyFailsToOpen() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let attacker = Curve25519.KeyAgreement.PrivateKey()
        let pub = recipient.publicKey.rawRepresentation.base64EncodedString()
        let sealed = try SealedBox.seal(Data("secret".utf8), to: pub, at: Date(timeIntervalSince1970: 1))
        XCTAssertThrowsError(try SealedBox.open(sealed, withRecipientPrivateKey: attacker))
    }

    func testEachSealUsesFreshEphemeralAndCiphertext() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let pub = recipient.publicKey.rawRepresentation.base64EncodedString()
        let a = try SealedBox.seal(Data("same".utf8), to: pub, at: Date(timeIntervalSince1970: 1))
        let b = try SealedBox.seal(Data("same".utf8), to: pub, at: Date(timeIntervalSince1970: 1))
        XCTAssertNotEqual(a.ephemeralPublicKeyB64, b.ephemeralPublicKeyB64)
        XCTAssertNotEqual(a.sealedB64, b.sealedB64)
    }

    func testRejectsMalformedRecipientKey() {
        XCTAssertThrowsError(try SealedBox.seal(Data("x".utf8), to: "not-base64!!", at: Date(timeIntervalSince1970: 1)))
    }
}

final class NotifierOutboxTests: XCTestCase {
    var dir: String!

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "wolf-nt-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        setenv("WOLF_HOME", dir + "/home", 1)
    }

    override func tearDownWithError() throws {
        unsetenv("WOLF_HOME")
        try? FileManager.default.removeItem(atPath: dir)
    }

    func testEnqueueAppendsSealedLinesOpenableOnlyByPartner() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let partner = PartnerChannel(
            publicKeyB64: recipient.publicKey.rawRepresentation.base64EncodedString(),
            channelId: "c1", relayURL: "https://relay.example",
            enrolledAt: Date(timeIntervalSince1970: 1))

        Notifier.enqueue("remove queued: a.com", to: partner, at: Date(timeIntervalSince1970: 2))
        Notifier.enqueue("panic", to: partner, at: Date(timeIntervalSince1970: 3))

        let raw = try String(contentsOfFile: Notifier.path, encoding: .utf8)
        let lines = raw.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2, "outbox is append-only, one JSON line per event")

        let events = try lines.map { try JSONDecoder().decode(SealedEvent.self, from: Data($0.utf8)) }
        let opened = try events.map {
            String(data: try SealedBox.open($0, withRecipientPrivateKey: recipient), encoding: .utf8)
        }
        XCTAssertEqual(opened, ["remove queued: a.com", "panic"])
    }
}
