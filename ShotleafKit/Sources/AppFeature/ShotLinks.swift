import AppKit
import Core
import Security

/// Expiring links to screenshots: Shotleaf's free service (server/links, on Cloudflare) unless the
/// user sets their own server (server/shots), whose key lives in the Keychain.
enum ShotLinks {
    static let serverKey = "shotsServer", hoursKey = "shotsHours"
    static let freeService = "https://s.syvyj.dev"
    static let choices = [1, 6, 12]
    /// What the free service takes (server/links/worker.js, MAX_BYTES).
    static let freeLimit = 5 * 1024 * 1024

    /// The user's own server, or the free service.
    static var server: String {
        let own = (UserDefaults.standard.string(forKey: serverKey) ?? "").trimmingCharacters(in: .whitespaces)
        return own.isEmpty ? freeService : own
    }
    static var ownServer: Bool { server != freeService }
    static var defaultHours: Int {
        let saved = UserDefaults.standard.object(forKey: hoursKey) as? Int ?? 6
        return choices.contains(saved) ? saved : 6
    }
    static var isSetUp: Bool { endpoint(server) != nil }

    enum Failure: LocalizedError {
        case notSetUp, rejected(String), noAnswer

        var errorDescription: String? {
            switch self {
            case .notSetUp: String(localized: "Set up the link server in Settings → Screenshot Links")
            case .rejected(let why): String(localized: "The server said no: \(why)")
            case .noAnswer: String(localized: "The server didn't answer as expected")
            }
        }
    }

    /// https://host[/path] → its /upload; plain http only for this Mac.
    static func endpoint(_ server: String) -> URL? {
        guard var parts = URLComponents(string: server.trimmingCharacters(in: .whitespaces)), let host = parts.host, !host.isEmpty,
              parts.scheme == "https" || (parts.scheme == "http" && ["localhost", "127.0.0.1"].contains(host))
        else { return nil }
        parts.path = parts.path.hasSuffix("/") ? parts.path + "upload" : parts.path + "/upload"
        parts.query = nil
        return parts.url
    }

    static func request(_ image: Data, hours: Int, server: String, token: String?) -> URLRequest? {
        guard let upload = endpoint(server), var parts = URLComponents(url: upload, resolvingAgainstBaseURL: false) else { return nil }
        parts.queryItems = [URLQueryItem(name: "ttl", value: String(hours * 3600))]
        guard let url = parts.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = image
        return request
    }

    /// A PNG too big for the free service becomes the best JPEG that fits (an own server takes it as it is).
    static func fitted(_ image: Data, server: String) async -> Data {
        guard server == freeService, image.count > freeLimit,
              let jpeg = await SmallFile.jpeg(png: image, under: freeLimit) else { return image }
        return jpeg
    }

    /// Uploads a PNG/JPEG; the link it can be opened at until it expires.
    /// The key goes only to the user's own server (the free service needs none, and reading it may ask for the password).
    @MainActor
    static func upload(_ image: Data, hours: Int, server: String = server, token: String? = ownServer ? token : nil) async throws -> URL {
        guard let request = request(await fitted(image, server: server), hours: hours, server: server, token: token) else { throw Failure.notSetUp }
        let (data, response) = try await URLSession.shared.data(for: request)
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 201 else {
            throw Failure.rejected(answer?["error"] as? String ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard let link = (answer?["url"] as? String).flatMap(URL.init(string:)) else { throw Failure.noAnswer }
        // The free service hands out a token per picture; an own server deletes with its key.
        links.add(Made(url: link, key: answer?["delete"] as? String ?? token, until: Date().addingTimeInterval(Double(hours) * 3600)))
        return link
    }

    // MARK: Taking a link down

    struct Made: Codable, Hashable { var url: URL, key: String?, until: Date }

    /// Links that still work, newest first; kept on disk so they can be deleted after a restart.
    @MainActor static let links = LinkList(file: AppInfo.supportFolder.appendingPathComponent("links.json"))

    /// The link made last, while it still works: the one "Delete last link" takes down.
    @MainActor static var last: Made? { links.active.first }

    static func removal(_ made: Made, key: String?) -> URLRequest {
        var request = URLRequest(url: made.url, timeoutInterval: 30)
        request.httpMethod = "DELETE"
        if let key = made.key ?? key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// Deletes a link's picture from the server. Already gone (404) counts as done.
    @MainActor
    static func delete(_ made: Made) async throws {
        // An own server's key isn't kept on disk: after a restart it comes from the Keychain.
        let (data, response) = try await URLSession.shared.data(for: removal(made, key: made.key == nil ? token : nil))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 204 || status == 404 else {
            let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw Failure.rejected(answer?["error"] as? String ?? "HTTP \(status)")
        }
        links.remove(made)
    }

    @MainActor
    static func deleteLast() async throws {
        if let made = last { try await delete(made) }
    }

    // MARK: Keychain

    private static let service = "dev.syvyj.shotleaf.links"

    /// Read once per launch (each Keychain read of an item Shotleaf didn't create asks for the password).
    @MainActor private static var cache: String??

    /// The key's old place (the app was called APILA): moved to `service` once.
    private static let oldService = "app.apila.shots"

    private static func query(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    /// The key, and whether the answer is final (found, or not there) rather than denied / locked.
    static func read(_ service: String) -> (key: String?, final: Bool) {
        var item: CFTypeRef?
        var query = query(service)
        query[kSecReturnData as String] = true
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let key = status == errSecSuccess ? (item as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
        return (key, status == errSecSuccess || status == errSecItemNotFound)
    }

    @MainActor static var token: String? {
        get {
            if let cache { return cache }
            let current = read(service)
            if let found = current.key {
                cache = .some(found)
                // macOS ties the item to the build that saved it (no Team ID to tie it to instead), so a new
                // build or another tool's key makes it ask every time; saved again by this build, it stops asking.
                if UserDefaults.standard.string(forKey: ownedKey) != buildHash { Self.token = found }
                return found
            }
            // Denied or locked: no answer yet, ask again next time instead of caching "no key".
            guard current.final else { return nil }
            let (old, final) = move(from: oldService, to: service)
            guard final else { return nil }
            if old != nil { UserDefaults.standard.set(buildHash, forKey: ownedKey) }
            cache = .some(old)
            return old
        }
        set {
            cache = .some(newValue)
            UserDefaults.standard.set(buildHash, forKey: ownedKey)
            save(newValue, in: service)
        }
    }

    /// Replaces the key in `service` (nil or empty: just removes it).
    static func save(_ key: String?, in service: String) {
        let query = query(service)
        SecItemDelete(query as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var add = query
        add[kSecAttrAccount as String] = "shotleaf"
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    /// A key left in `old` goes to `service`; `old` is emptied only once the key is safely in its new place.
    static func move(from old: String, to service: String) -> (key: String?, final: Bool) {
        let found = read(old)
        guard found.final, let key = found.key else { return found }
        save(key, in: service)
        if read(service).key == key { SecItemDelete(query(old) as CFDictionary) }
        return found
    }

    private static let ownedKey = "shotsKeyOwnedBy"

    /// This build's code hash (what the Keychain item is tied to).
    private static let buildHash: String? = {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }()
}

/// The links made and not yet expired, saved as JSON so they can be deleted after a restart.
@MainActor @Observable
final class LinkList {
    private let file: URL
    private(set) var items: [ShotLinks.Made]

    init(file: URL) {
        self.file = file
        items = (try? JSONDecoder().decode([ShotLinks.Made].self, from: Data(contentsOf: file))) ?? []
    }

    var active: [ShotLinks.Made] { items.filter { $0.until > Date() } }

    func add(_ made: ShotLinks.Made) { save([made] + active) }
    func remove(_ made: ShotLinks.Made) { save(active.filter { $0 != made }) }

    private func save(_ new: [ShotLinks.Made]) {
        items = new
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Only the free service's per-picture tokens go to disk; an own server's key stays in the Keychain.
        let kept = new.map { $0.url.host() == URL(string: ShotLinks.freeService)?.host() ? $0 : ShotLinks.Made(url: $0.url, key: nil, until: $0.until) }
        try? JSONEncoder().encode(kept).write(to: file, options: [.atomic, .completeFileProtection])
    }
}
