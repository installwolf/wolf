import XCTest
@testable import WolfCore

/// Pure logic behind `wolf bootstrap` — the one privileged step a Homebrew user
/// runs after `brew install`. Only the string-rendering is unit-tested here; the
/// actual file copies / launchctl calls are thin side effects in the CLI.
final class BootstrapTests: XCTestCase {

    // MARK: pf.conf wiring (idempotent)

    func testWiringAppendsAnchorAndLoadLines() throws {
        let existing = "scrub-anchor \"com.apple/*\"\nnat-anchor \"com.apple/*\"\n"
        let wired = try XCTUnwrap(PfConf.wire(into: existing, anchorPath: "/etc/pf.anchors/wolf"))
        XCTAssertTrue(wired.contains(existing))                       // preserves what was there
        XCTAssertTrue(wired.contains("anchor \"wolf\""))
        XCTAssertTrue(wired.contains("load anchor \"wolf\" from \"/etc/pf.anchors/wolf\""))
    }

    func testWiringIsIdempotent() {
        let already = "anchor \"wolf\"\nload anchor \"wolf\" from \"/etc/pf.anchors/wolf\"\n"
        XCTAssertNil(PfConf.wire(into: already, anchorPath: "/etc/pf.anchors/wolf"),
                     "already-wired pf.conf must return nil (no rewrite)")
    }

    func testWiringDetectsAnchorEvenWithOddSpacing() {
        // pf tolerates extra whitespace; our detection must too, so we never double-wire.
        let already = "anchor   \"wolf\"\n"
        XCTAssertNil(PfConf.wire(into: already, anchorPath: "/etc/pf.anchors/wolf"))
    }

    // MARK: LaunchDaemon plist

    func testPlistRendersDaemonPathAndKeepAlive() {
        let plist = DaemonPlist.render(wolfdPath: "/usr/local/sbin/wolfd")
        XCTAssertTrue(plist.contains("<string>com.wolf.daemon</string>"))
        XCTAssertTrue(plist.contains("<string>/usr/local/sbin/wolfd</string>"))
        XCTAssertTrue(plist.contains("<key>KeepAlive</key>"))
        XCTAssertTrue(plist.contains("<key>RunAtLoad</key>"))
        // Must be parseable as a real plist.
        let data = Data(plist.utf8)
        XCTAssertNoThrow(try PropertyListSerialization.propertyList(from: data, options: [], format: nil))
    }
}
