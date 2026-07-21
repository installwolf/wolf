import XCTest
@testable import BulwarkCore

final class DomainTests: XCTestCase {
    func testCanonicalizesCommonForms() {
        XCTAssertEqual(Domain.canonical("Example.com"), "example.com")
        XCTAssertEqual(Domain.canonical("  example.com  "), "example.com")
        XCTAssertEqual(Domain.canonical("https://example.com"), "example.com")
        XCTAssertEqual(Domain.canonical("http://example.com/some/path?x=1"), "example.com")
        XCTAssertEqual(Domain.canonical("www.example.com"), "example.com")
        XCTAssertEqual(Domain.canonical("EXAMPLE.com:8080"), "example.com")
        XCTAssertEqual(Domain.canonical("sub.example.co.uk"), "sub.example.co.uk")
    }

    func testRejectsInvalid() {
        XCTAssertNil(Domain.canonical(""))
        XCTAssertNil(Domain.canonical("   "))
        XCTAssertNil(Domain.canonical("nodot"))
        XCTAssertNil(Domain.canonical("bad domain.com"))
        XCTAssertNil(Domain.canonical("http://"))
    }
}

final class HostsRendererTests: XCTestCase {
    func testRendersBlockWithMarkersAndVariants() {
        let out = HostsRenderer.managedBlock(["example.com"])
        XCTAssertTrue(out.contains(HostsRenderer.beginMarker))
        XCTAssertTrue(out.contains(HostsRenderer.endMarker))
        XCTAssertTrue(out.contains("0.0.0.0 example.com"))
        XCTAssertTrue(out.contains("0.0.0.0 www.example.com"))
    }

    func testSpliceReplacesExistingManagedSection() {
        let base = "127.0.0.1 localhost\n"
        let first = HostsRenderer.splice(into: base, domains: ["a.com"])
        XCTAssertTrue(first.contains("127.0.0.1 localhost"))
        XCTAssertTrue(first.contains("0.0.0.0 a.com"))

        // Re-splicing with a different set must not duplicate or leave stale entries.
        let second = HostsRenderer.splice(into: first, domains: ["b.com"])
        XCTAssertTrue(second.contains("127.0.0.1 localhost"))
        XCTAssertTrue(second.contains("0.0.0.0 b.com"))
        XCTAssertFalse(second.contains("0.0.0.0 a.com"))
        // Exactly one managed block.
        let occurrences = second.components(separatedBy: HostsRenderer.beginMarker).count - 1
        XCTAssertEqual(occurrences, 1)
    }
}

final class PfRendererTests: XCTestCase {
    func testBlocksKnownDoHAndDoT() {
        let rules = PfRenderer.anchorRules()
        XCTAssertTrue(rules.contains("1.1.1.1"))
        XCTAssertTrue(rules.contains("8.8.8.8"))
        XCTAssertTrue(rules.contains("port 853")) // DoT
    }
}

final class PassphraseTests: XCTestCase {
    func testVerifyRoundTrip() throws {
        let h = try Passphrase.make("correct horse battery staple")
        XCTAssertTrue(Passphrase.verify("correct horse battery staple", against: h))
        XCTAssertFalse(Passphrase.verify("wrong", against: h))
    }

    func testSaltIsRandomPerHash() throws {
        let a = try Passphrase.make("same")
        let b = try Passphrase.make("same")
        XCTAssertNotEqual(a.saltB64, b.saltB64)
        XCTAssertNotEqual(a.hashB64, b.hashB64)
    }
}

final class StateTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func makeState(cooldown: TimeInterval = 48 * 3600) -> BulwarkState {
        BulwarkState(blocked: [], pendingRemovals: [],
                     config: BulwarkConfig(cooldownSeconds: cooldown, passphrase: nil))
    }

    func testAddIsInstantAndCanonicalizes() {
        var s = makeState()
        XCTAssertEqual(s.add("https://www.PornHub.com/foo"), "pornhub.com")
        XCTAssertTrue(s.blocked.contains("pornhub.com"))
        // adding again is idempotent
        XCTAssertEqual(s.add("pornhub.com"), "pornhub.com")
        XCTAssertEqual(s.blocked.count, 1)
    }

    func testRemoveQueuesWithCooldownAndStaysBlocked() {
        var s = makeState()
        _ = s.add("a.com")
        let req = s.requestRemoval("a.com", now: t0)
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.unlockAt, t0.addingTimeInterval(48 * 3600))
        // still blocked during cooldown
        XCTAssertTrue(s.blocked.contains("a.com"))
        XCTAssertEqual(s.pendingRemovals.count, 1)
    }

    func testDrainDueRemovesOnlyAfterUnlock() {
        var s = makeState()
        _ = s.add("a.com")
        _ = s.requestRemoval("a.com", now: t0)
        // one minute before unlock: nothing drains
        XCTAssertEqual(s.drainDue(now: t0.addingTimeInterval(48 * 3600 - 60)), [])
        XCTAssertTrue(s.blocked.contains("a.com"))
        // at unlock time: drains
        XCTAssertEqual(s.drainDue(now: t0.addingTimeInterval(48 * 3600)), ["a.com"])
        XCTAssertFalse(s.blocked.contains("a.com"))
        XCTAssertTrue(s.pendingRemovals.isEmpty)
    }

    func testPassphraseRemovalIsInstant() throws {
        var s = makeState()
        s.config.passphrase = try Passphrase.make("partner-secret")
        _ = s.add("a.com")
        XCTAssertFalse(s.removeWithPassphrase("a.com", passphrase: "nope"))
        XCTAssertTrue(s.blocked.contains("a.com"))
        XCTAssertTrue(s.removeWithPassphrase("a.com", passphrase: "partner-secret"))
        XCTAssertFalse(s.blocked.contains("a.com"))
    }

    func testAddingBackCancelsPendingRemoval() {
        var s = makeState()
        _ = s.add("a.com")
        _ = s.requestRemoval("a.com", now: t0)
        XCTAssertEqual(s.pendingRemovals.count, 1)
        _ = s.add("a.com") // change of heart, re-commit
        XCTAssertTrue(s.pendingRemovals.isEmpty)
        XCTAssertTrue(s.blocked.contains("a.com"))
    }

    func testCodableRoundTrip() throws {
        var s = makeState()
        _ = s.add("a.com")
        _ = s.requestRemoval("a.com", now: t0)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(BulwarkState.self, from: data)
        XCTAssertEqual(s, back)
    }
}
