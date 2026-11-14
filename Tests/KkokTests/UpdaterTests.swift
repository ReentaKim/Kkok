import XCTest
@testable import Kkok

final class UpdaterTests: XCTestCase {
    func testCompareVersions() {
        XCTAssertEqual(Updater.compare("0.2.1", "0.2.0"), 1)
        XCTAssertEqual(Updater.compare("0.10.0", "0.9.9"), 1)
        XCTAssertEqual(Updater.compare("1.0", "1.0.0"), 0)
        XCTAssertEqual(Updater.compare("0.2.0", "0.2.1"), -1)
    }

    func testParseReleaseWithDigest() throws {
        let json = """
        {"tag_name":"v0.3.0","html_url":"https://github.com/ReentaKim/Kkok/releases/tag/v0.3.0","body":"notes",
         "assets":[{"name":"Other.zip","browser_download_url":"https://x/y.zip"},
                   {"name":"Kkok-0.3.0.zip","browser_download_url":"https://github.com/ReentaKim/Kkok/releases/download/v0.3.0/Kkok-0.3.0.zip",
                    "digest":"sha256:ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789"}]}
        """
        let r = try XCTUnwrap(Updater.parse(Data(json.utf8)))
        XCTAssertEqual(r.version, "0.3.0")
        XCTAssertEqual(r.zipURL?.lastPathComponent, "Kkok-0.3.0.zip")
        XCTAssertEqual(r.sha256, "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789")
    }

    /// digest가 없으면 릴리스 설명의 `SHA-256` 값을 쓴다
    func testParseReleaseShaFromBody() throws {
        let sha = String(repeating: "a1", count: 32)
        let json = """
        {"tag_name":"v0.3.0","body":"SHA-256: `\(sha)`","assets":[{"name":"Kkok-0.3.0.zip","browser_download_url":"https://g/z.zip"}]}
        """
        let r = try XCTUnwrap(Updater.parse(Data(json.utf8)))
        XCTAssertEqual(r.sha256, sha)
    }

    func testParseWithoutZipAsset() throws {
        let r = try XCTUnwrap(Updater.parse(Data(#"{"tag_name":"v1.0.0","assets":[]}"#.utf8)))
        XCTAssertNil(r.zipURL)
    }

    func testSHA256OfFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kkok-sha-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try Updater.sha256(of: url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
