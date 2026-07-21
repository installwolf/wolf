import XCTest
@testable import WolfCore

/// Stub resolver so command tests never touch the network. Unmapped domains
/// fall back to `.reachable`, so existing tests behave as before.
struct StubResolver: DomainResolver {
    var map: [String: DomainReachability] = [:]
    var fallback: DomainReachability = .reachable
    func check(_ domain: String) -> DomainReachability { map[domain] ?? fallback }
}

/// Exercises the shared command processor (used by both the daemon socket and
/// the CLI root-fallback) against sandbox paths, including the gate.
final class CommandProcessorTests: XCTestCase {
    var dir: String!
    let store = Store()

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "wolf-cp-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        setenv("WOLF_HOME", dir + "/home", 1)
        setenv("WOLF_HOSTS", dir + "/hosts", 1)
        setenv("WOLF_PF_ANCHOR", dir + "/pf.anchor", 1)
        try "127.0.0.1 localhost\n".write(toFile: dir + "/hosts", atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws {
        for k in ["WOLF_HOME", "WOLF_HOSTS", "WOLF_PF_ANCHOR"] { unsetenv(k) }
        try? FileManager.default.removeItem(atPath: dir)
    }

    func run(_ cmd: String, _ args: [String], pass: String? = nil, now: Date = Date(),
             resolver: DomainResolver = StubResolver()) -> CommandResult {
        CommandProcessor.handle(CommandRequest(cmd: cmd, args: args, passphrase: pass),
                                store: store, now: now, resolver: resolver)
    }

    func testAddThenGateThenCancel() throws {
        // add is instant and writes the sinkhole
        var r = run("add", ["evil.com"])
        XCTAssertTrue(r.ok)
        XCTAssertTrue(try String(contentsOfFile: dir + "/hosts", encoding: .utf8).contains("0.0.0.0 evil.com"))

        // protected domains are refused
        r = run("add", ["icloud.com"])
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.lines.contains { $0.contains("protected") })

        // remove queues (stays blocked), reported with an unlock time
        r = run("remove", ["evil.com"])
        XCTAssertTrue(r.ok)
        XCTAssertTrue(r.lines.contains { $0.contains("removal queued") })
        XCTAssertTrue(try store.load().blocked.contains("evil.com"))

        // cancel keeps it blocked
        r = run("cancel", ["evil.com"])
        XCTAssertTrue(r.ok)
        XCTAssertTrue(try store.load().pendingRemovals.isEmpty)
    }

    func testAddRefusesNonexistentDomain() throws {
        let r = run("add", ["exampl.com"],
                    resolver: StubResolver(map: ["exampl.com": .notFound]))
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.lines.contains { $0.contains("doesn't resolve") })
        XCTAssertFalse(try store.load().blocked.contains("exampl.com"))
    }

    func testForceOverridesResolutionCheck() throws {
        let r = run("add", ["exampl.com", "--force"],
                    resolver: StubResolver(map: ["exampl.com": .notFound]))
        XCTAssertTrue(r.ok)
        XCTAssertTrue(try store.load().blocked.contains("exampl.com"))
    }

    func testAddAllowsWhenOffline() throws {
        // `.unknown` means we couldn't tell (no DNS) — fail open, don't trap the user.
        let r = run("add", ["realsite.com"],
                    resolver: StubResolver(map: ["realsite.com": .unknown]))
        XCTAssertTrue(r.ok)
        XCTAssertTrue(try store.load().blocked.contains("realsite.com"))
    }

    func testResolutionCheckSkippedForAlreadyBlocked() throws {
        _ = run("add", ["evil.com"])   // reachable via fallback
        // Re-adding a blocked domain must not re-run the check (it now sinkholes
        // to 0.0.0.0, and re-committing should always succeed).
        let r = run("add", ["evil.com"],
                    resolver: StubResolver(map: ["evil.com": .notFound]))
        XCTAssertTrue(r.lines.contains { $0.contains("already blocked") })
    }

    func testInstantRemoveNeedsPassphrase() throws {
        _ = run("add", ["evil.com"])
        // no passphrase configured → --now refused
        var r = run("remove", ["evil.com", "--now"], pass: "whatever")
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.lines.contains { $0.contains("no partner passphrase") })

        // set a passphrase, then wrong vs right
        var s = try store.load()
        s.config.passphrase = try Passphrase.make("secret")
        try store.save(s)
        r = run("remove", ["evil.com", "--now"], pass: "wrong")
        XCTAssertFalse(r.ok)
        r = run("remove", ["evil.com", "--now"], pass: "secret")
        XCTAssertTrue(r.ok)
        XCTAssertFalse(try store.load().blocked.contains("evil.com"))
    }
}
