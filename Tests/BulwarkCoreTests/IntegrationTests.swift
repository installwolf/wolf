import XCTest
@testable import BulwarkCore

/// Exercises the real Store + Enforcer (hosts layer) against sandbox paths, and
/// simulates a daemon drain cycle. No root and no pf/DNS spawns.
final class IntegrationTests: XCTestCase {
    var dir: String!

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "bulwark-it-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        setenv("BULWARK_HOME", dir + "/home", 1)
        setenv("BULWARK_HOSTS", dir + "/hosts", 1)
        setenv("BULWARK_PF_ANCHOR", dir + "/pf.anchor", 1)
        // Seed a hosts file with pre-existing user content.
        try "127.0.0.1 localhost\n".write(toFile: dir + "/hosts", atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        for k in ["BULWARK_HOME", "BULWARK_HOSTS", "BULWARK_PF_ANCHOR"] { unsetenv(k) }
        try? FileManager.default.removeItem(atPath: dir)
    }

    func testStorePersistsAndHostsSinkholesWhilePreservingUserLines() throws {
        let store = Store()
        var s = try store.load()
        XCTAssertEqual(s.add("evil.com"), "evil.com")
        try store.save(s)
        try Enforcer.writeHosts(s.blocked.sorted())

        let reloaded = try store.load()
        XCTAssertTrue(reloaded.blocked.contains("evil.com"))

        let hosts = try String(contentsOfFile: dir + "/hosts", encoding: .utf8)
        XCTAssertTrue(hosts.contains("127.0.0.1 localhost"))   // user line preserved
        XCTAssertTrue(hosts.contains("0.0.0.0 evil.com"))
    }

    func testDaemonCycleDrainsDueRemovalAndClearsHosts() throws {
        let store = Store()
        var s = try store.load()
        _ = s.add("evil.com")
        // Queue a removal that is already past due.
        let past = Date(timeIntervalSinceNow: -10)
        s.pendingRemovals.append(RemovalRequest(domain: "evil.com",
                                                requestedAt: past.addingTimeInterval(-1),
                                                unlockAt: past))
        try store.save(s)
        try Enforcer.writeHosts(s.blocked.sorted())
        XCTAssertTrue(try String(contentsOfFile: dir + "/hosts", encoding: .utf8).contains("0.0.0.0 evil.com"))

        // Simulate one daemon cycle.
        var live = try store.load()
        let drained = live.drainDue(now: Date())
        XCTAssertEqual(drained, ["evil.com"])
        try store.save(live)
        try Enforcer.writeHosts(live.blocked.sorted())

        let hosts = try String(contentsOfFile: dir + "/hosts", encoding: .utf8)
        XCTAssertFalse(hosts.contains("0.0.0.0 evil.com"))     // gone after cooldown
        XCTAssertTrue(hosts.contains("127.0.0.1 localhost"))   // user line still there
    }
}
