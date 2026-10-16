import AppKit
import Core

/// The newest Shotleaf release on GitHub. Asked once a day (Settings → General);
/// nothing about the user goes with the request.
public enum Updates {
    public struct Release: Equatable, Sendable {
        public let version: String
        public let download: URL
    }

    static let api = URL(string: "https://api.github.com/repos/Syvyj/shotleaf/releases/latest")!

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// "0.10.0" is newer than "0.9.1"; a leading "v" is ignored.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let parts = { (s: String) in s.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").map { Int($0) ?? 0 } }
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
        struct Answer: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let assets: [Asset]
        }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        let dmg = answer.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url ?? AppInfo.releases
        return Release(version: answer.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v")), download: dmg)
    }
}
