import Testing
import Foundation
@testable import AppFeature

@Test("Versions compare by number, not as text")
func updateVersions() {
    #expect(Updates.isNewer("0.10.0", than: "0.9.1"))
    #expect(Updates.isNewer("v0.2", than: "0.1.9"))
    #expect(!Updates.isNewer("0.1.0", than: "0.1"))
    #expect(!Updates.isNewer("0.1.0", than: "0.2.0"))
    #expect(Updates.isNewer("V0.2.0", than: "0.1.9"))                   // a capital V too
    #expect(!Updates.isNewer("", than: "0.1"))
    #expect(!Updates.isNewer("0.2.0-beta", than: "0.2.0"))             // a pre-release is never offered over the release
}

@Test("The checksum file gives its SHA-256, anything else gives nothing")
func updateChecksum() {
    let hex = String(repeating: "ab", count: 32)
    #expect(Updates.checksum(in: "\(hex.uppercased())  Shotleaf.dmg\n") == hex)
    #expect(Updates.checksum(in: "not a checksum") == nil)
    #expect(Updates.checksum(in: "") == nil)
    #expect(Updates.checksum(in: String(hex.dropLast())) == nil && Updates.checksum(in: hex + "a") == nil) // 63, 65
}

@Test("GitHub's latest-release answer gives the version, the disk image and its checksum file")
func updateAnswer() throws {
    let answer = """
        {"tag_name": "v0.2.0", "name": "Shotleaf 0.2.0", "assets": [
          {"name": "Shotleaf.dmg.sha256", "browser_download_url": "https://github.com/Syvyj/shotleaf/releases/download/v0.2.0/Shotleaf.dmg.sha256"},
          {"name": "Shotleaf.dmg", "browser_download_url": "https://github.com/Syvyj/shotleaf/releases/download/v0.2.0/Shotleaf.dmg"}]}
        """
    let release = try Updates.release(from: Data(answer.utf8))
    #expect(release.version == "0.2.0")
    #expect(release.download.lastPathComponent == "Shotleaf.dmg" && release.checksum?.lastPathComponent == "Shotleaf.dmg.sha256")
    // No checksum file: nothing to check the download against, so `prepare` refuses it.
    let bare = try Updates.release(from: Data(#"{"tag_name": "V0.3", "assets": []}"#.utf8))
    #expect(bare.version == "0.3" && bare.checksum == nil)
    #expect(throws: (any Error).self) { try Updates.release(from: Data("<html>rate limited</html>".utf8)) }
}
