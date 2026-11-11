import Testing
import Foundation
import CryptoKit
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

@Test("The release's assets: the signed checksum is found too")
func updateSignatureAsset() throws {
    let answer = """
        {"tag_name": "v0.2.1", "assets": [{"name": "Shotleaf.dmg", "browser_download_url": "https://example.com/Shotleaf.dmg"},
          {"name": "Shotleaf.dmg.sha256", "browser_download_url": "https://example.com/Shotleaf.dmg.sha256"},
          {"name": "Shotleaf.dmg.sha256.sig", "browser_download_url": "https://example.com/Shotleaf.dmg.sha256.sig"}]}
        """
    let release = try Updates.release(from: Data(answer.utf8))
    #expect(release.checksum?.lastPathComponent == "Shotleaf.dmg.sha256" && release.signature?.lastPathComponent == "Shotleaf.dmg.sha256.sig")
    #expect(Data(base64Encoded: Updates.publicKey)?.count == 32) // a real Ed25519 public key is built in
}

/// A release on disk: a disk image with a "Shotleaf.app" in it, its checksum file, and that file signed.
@Suite("Installing an update")
struct UpdatePrepareTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotleaf-update-test-\(UUID())")
    let key = Curve25519.Signing.PrivateKey()
    var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }

    /// `sums`: what goes in the checksum file (nil: the image's real one).
    func release(sums: String? = nil, signedBy signer: Curve25519.Signing.PrivateKey? = nil, withSignature: Bool = true) throws -> Updates.Release {
        let app = dir.appendingPathComponent("src/Shotleaf.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: app.appendingPathComponent("marker"))
        let dmg = dir.appendingPathComponent("Shotleaf.dmg")
        if !FileManager.default.fileExists(atPath: dmg.path) {
            let make = Process()
            make.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            make.arguments = ["create", "-quiet", "-fs", "HFS+", "-srcfolder", dir.appendingPathComponent("src").path, "-volname", "Shotleaf", dmg.path]
            try make.run(); make.waitUntilExit()
        }
        let digest = SHA256.hash(data: try Data(contentsOf: dmg)).map { String(format: "%02x", $0) }.joined()
        let sumFile = dir.appendingPathComponent("Shotleaf.dmg.sha256"), sigFile = dir.appendingPathComponent("Shotleaf.dmg.sha256.sig")
        let sumData = Data((sums ?? "\(digest)  Shotleaf.dmg\n").utf8)
        try sumData.write(to: sumFile)
        try Data(try (signer ?? key).signature(for: Data("\(digest)  Shotleaf.dmg\n".utf8)).base64EncodedString().utf8).write(to: sigFile)
        return Updates.Release(version: "9.9.9", download: dmg, checksum: sumFile, signature: withSignature ? sigFile : nil)
    }

    func prepare(_ release: Updates.Release, signedLike: Bool = true) async throws -> URL {
        let into = dir.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: into, withIntermediateDirectories: true)
        return try await Updates.prepare(release, into: into, key: publicKey, signedLike: { _ in signedLike })
    }

    @Test("A release signed with the update key, matching its checksum and signed like this app, is staged next to it")
    func installs() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let staged = try await prepare(try release())
        #expect(staged.lastPathComponent == ".Shotleaf-update.app")
        #expect(try Data(contentsOf: staged.appendingPathComponent("Contents/marker")) == Data("new".utf8))
    }

    @Test("Refused, before the image is opened: no signature, another key's signature, a checksum file changed after signing")
    func refusesUnsigned() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: Updates.Failure.unsigned) { try await prepare(try release(withSignature: false)) }
        await #expect(throws: Updates.Failure.unsigned) { try await prepare(try release(signedBy: Curve25519.Signing.PrivateKey())) }
        await #expect(throws: Updates.Failure.unsigned) { try await prepare(try release(sums: String(repeating: "0", count: 64) + "  Shotleaf.dmg\n")) }
    }

    @Test("Refused: an app inside that isn't signed like this one, and it isn't left behind")
    func refusesOtherSigner() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: Updates.Failure.signature) { try await prepare(try release(), signedLike: false) }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Applications/.Shotleaf-update.app").path))
    }
}

