import AppKit
import Core
import CryptoKit
import Security

/// The newest Shotleaf release on GitHub. Asked once a day (Settings → General);
/// nothing about the user goes with the request.
public enum Updates {
    public struct Release: Equatable, Sendable {
        public let version: String
        public let download: URL
        /// The release's "Shotleaf.dmg.sha256", needed to install it from inside the app.
        public let checksum: URL?
        /// "Shotleaf.dmg.sha256.sig": the checksum file signed with the update key (from 0.2.1).
        public var signature: URL? = nil
    }

    /// The public half of the update key (scripts/update-key.swift, ADR-0070). Only a checksum
    /// file signed with its private half is trusted, so a disk image is opened only if it's ours.
    nonisolated static let publicKey = "1ypqplg/J5P21FJp0MOevR0EN3Qwxm4xsqcHVw9zn0M="

    /// The checksum file was signed with the update key.
    nonisolated static func signed(_ sums: Data, signature: Data, key: String = publicKey) -> Bool {
        guard let raw = Data(base64Encoded: key), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              let signature = Data(base64Encoded: String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return key.isValidSignature(signature, for: sums)
    }

    static let api = URL(string: "https://api.github.com/repos/Syvyj/shotleaf/releases/latest")!

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// "0.10.0" is newer than "0.9.1"; a leading "v" is ignored.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let parts = { (s: String) in s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    static func latest() async throws -> Release {
        var request = URLRequest(url: api, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try release(from: data)
    }

    /// GitHub's answer for the latest release → its version, disk image and checksum file.
    nonisolated static func release(from data: Data) throws -> Release {
        struct Answer: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let assets: [Asset]
        }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        let dmg = answer.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url ?? AppInfo.releases
        let sum = answer.assets.first { $0.name.hasSuffix(".dmg.sha256") }?.browser_download_url
        let signature = answer.assets.first { $0.name.hasSuffix(".dmg.sha256.sig") }?.browser_download_url
        return Release(version: answer.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), download: dmg, checksum: sum,
                       signature: signature)
    }

    // MARK: Installing

    /// Why an update couldn't be installed; the user can still download it by hand.
    enum Failure: LocalizedError {
        case notWritable, checksum, unsigned, signature, unpack

        var errorDescription: String? {
            switch self {
            case .notWritable: String(localized: "Shotleaf can’t replace itself in the folder it’s in.")
            case .checksum: String(localized: "The download doesn’t match the release.")
            case .unsigned: String(localized: "This release isn’t signed with Shotleaf’s update key.")
            case .signature: String(localized: "The downloaded app isn’t signed like this one.")
            case .unpack: String(localized: "The downloaded disk image couldn’t be opened.")
            }
        }
    }

    /// "5e1c…  Shotleaf.dmg" → "5e1c…" (a SHA-256 in hex), else nil.
    nonisolated static func checksum(in file: String) -> String? {
        guard let first = file.split(whereSeparator: \.isWhitespace).first?.lowercased(),
              first.count == 64, first.allSatisfy(\.isHexDigit) else { return nil }
        return first
    }

    /// Downloads the release, checks it against its checksum and against this app's own
    /// signature (same identifier, same certificate), and puts the new copy next to this
    /// one. Downloaded by the app itself, it isn't marked as from the internet, so macOS
    /// doesn't ask again on its first launch.
    /// `folder`, `key` and `signedLike` are this app's own; tests give theirs.
    static func prepare(_ release: Release, into folder: URL = Bundle.main.bundleURL.deletingLastPathComponent(), key: String = publicKey,
                        signedLike: (URL) -> Bool = signedLikeThisApp) async throws -> URL {
        guard FileManager.default.isWritableFile(atPath: folder.path) else { throw Failure.notWritable }
        guard let sumURL = release.checksum else { throw Failure.checksum }
        guard let signatureURL = release.signature else { throw Failure.unsigned }
        let (sum, _) = try await URLSession.shared.data(from: sumURL)
        let (signature, _) = try await URLSession.shared.data(from: signatureURL)
        // Before anything is downloaded or opened: the checksum file is ours.
        guard signed(sum, signature: signature, key: key) else { throw Failure.unsigned }
        let (dmg, _) = try await URLSession.shared.download(from: release.download)
        defer { try? FileManager.default.removeItem(at: dmg) }
        let digest = SHA256.hash(data: try Data(contentsOf: dmg)).map { String(format: "%02x", $0) }.joined()
        guard checksum(in: String(decoding: sum, as: UTF8.self)) == digest else { throw Failure.checksum }

        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("shotleaf-update-\(UUID().uuidString)")
        guard run("/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path) else { throw Failure.unpack }
        defer { _ = run("/usr/bin/hdiutil", "detach", mount.path, "-force") }
        let staged = folder.appendingPathComponent(".Shotleaf-update.app")
        try? FileManager.default.removeItem(at: staged)
        guard run("/usr/bin/ditto", mount.appendingPathComponent("Shotleaf.app").path, staged.path) else { throw Failure.unpack }
        guard signedLike(staged) else {
            try? FileManager.default.removeItem(at: staged)
            throw Failure.signature
        }
        return staged
    }

    /// The new copy passes this app's designated requirement: for Shotleaf that's its
    /// bundle identifier and the leaf certificate it's signed with.
    static func signedLikeThisApp(_ app: URL) -> Bool {
        var me: SecCode?, mine: SecStaticCode?, requirement: SecRequirement?, other: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &mine) == errSecSuccess, let mine,
              SecCodeCopyDesignatedRequirement(mine, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &other) == errSecSuccess, let other
        else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(other, flags, requirement) == errSecSuccess
    }

    /// Once this app has quit: the new copy takes its place (the old one comes back if
    /// that fails) and starts. Same place and signature, so the permissions stay.
    @MainActor
    static func swapAndRelaunch(_ staged: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done
            rm -rf "$2"
            if mv "$0" "$2" && mv "$1" "$0"; then rm -rf "$2"; else [ -d "$0" ] || mv "$2" "$0"; fi
            open "$0"
            """, Bundle.main.bundlePath, staged.path, Bundle.main.bundlePath + ".old"]
        try? task.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: String...) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
