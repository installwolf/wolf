import XCTest
@testable import WolfCore

final class FlowInspectTests: XCTestCase {

    // Build a minimal TLS 1.2 ClientHello record carrying one SNI host_name.
    private func clientHello(sni: String) -> Data {
        let host = Array(sni.utf8)
        func u16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xff), UInt8(v & 0xff)] }

        // server_name extension body
        var sniEntry: [UInt8] = [0x00]        // name_type = host_name
        sniEntry += u16(host.count) + host
        var serverNameList = u16(sniEntry.count) + sniEntry
        var sniExt = u16(0x0000) + u16(serverNameList.count) + serverNameList

        var exts = sniExt
        var body: [UInt8] = [0x03, 0x03]      // client_version TLS 1.2
        body += [UInt8](repeating: 0x00, count: 32) // random
        body += [0x00]                        // session_id length 0
        body += u16(2) + [0x00, 0x2f]         // cipher_suites (one)
        body += [0x01, 0x00]                  // compression_methods (null)
        body += u16(exts.count) + exts        // extensions

        var handshake: [UInt8] = [0x01]       // ClientHello
        handshake += [UInt8(body.count >> 16 & 0xff), UInt8(body.count >> 8 & 0xff), UInt8(body.count & 0xff)]
        handshake += body

        var record: [UInt8] = [0x16, 0x03, 0x01] // handshake, TLS 1.0 record version
        record += u16(handshake.count) + handshake
        return Data(record)
    }

    func testExtractsSNIFromClientHello() {
        XCTAssertEqual(TLSInspect.sniHostName(clientHello(sni: "www.pornhub.com")), "www.pornhub.com")
        XCTAssertEqual(TLSInspect.sniHostName(clientHello(sni: "Example.COM")), "example.com") // lowercased
    }

    func testTruncatedOrNonHandshakeReturnsNil() {
        XCTAssertNil(TLSInspect.sniHostName(Data([0x16, 0x03, 0x01])))       // too short
        XCTAssertNil(TLSInspect.sniHostName(Data([0x17, 0x03, 0x03, 0x00]))) // not a handshake
        let full = clientHello(sni: "example.com")
        XCTAssertNil(TLSInspect.sniHostName(full.prefix(20)))                 // truncated mid-hello
    }

    func testHTTPHostHeader() {
        let req = "GET /videos HTTP/1.1\r\nHost: www.pornhub.com\r\nAccept: */*\r\n\r\n"
        XCTAssertEqual(HTTPInspect.hostHeader(Data(req.utf8)), "www.pornhub.com")
        let withPort = "GET / HTTP/1.1\r\nhost: Example.com:8080\r\n\r\n" // case-insensitive, strip port
        XCTAssertEqual(HTTPInspect.hostHeader(Data(withPort.utf8)), "example.com")
        XCTAssertNil(HTTPInspect.hostHeader(Data("not http".utf8)))
    }

    func testIsBlockedMatchesApexAndSubdomains() {
        let blocked: Set<String> = ["pornhub.com", "xvideos.com"]
        XCTAssertTrue(Rules.isBlocked("pornhub.com", in: blocked))
        XCTAssertTrue(Rules.isBlocked("www.pornhub.com", in: blocked))
        XCTAssertTrue(Rules.isBlocked("cdn.ee.pornhub.com", in: blocked))
        XCTAssertTrue(Rules.isBlocked("PORNHUB.com", in: blocked))      // case-insensitive
        XCTAssertTrue(Rules.isBlocked("pornhub.com.", in: blocked))     // trailing dot
        XCTAssertFalse(Rules.isBlocked("notpornhub.com", in: blocked))  // not a subdomain
        XCTAssertFalse(Rules.isBlocked("pornhub.com.evil.com", in: blocked))
        XCTAssertFalse(Rules.isBlocked("example.com", in: blocked))
    }
}
