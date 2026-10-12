import Foundation
import Security

/// Expiring links to screenshots, on the user's own server (server/shots).
/// The address is a setting; the key lives in the Keychain.
enum ShotLinks {
    static let serverKey = "shotsServer", hoursKey = "shotsHours"
    static let choices = [1, 6, 24]

    static var server: String { UserDefaults.standard.string(forKey: serverKey) ?? "" }
    static var defaultHours: Int { UserDefaults.standard.object(forKey: hoursKey) as? Int ?? 6 }
    static var isSetUp: Bool { endpoint(server) != nil && !(token ?? "").isEmpty }

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

    static func request(_ image: Data, hours: Int, server: String, token: String) -> URLRequest? {
        guard let upload = endpoint(server), var parts = URLComponents(url: upload, resolvingAgainstBaseURL: false) else { return nil }
        parts.queryItems = [URLQueryItem(name: "ttl", value: String(hours * 3600))]
        guard let url = parts.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = image
        return request
    }

    /// Uploads a PNG/JPEG; the link it can be opened at until it expires.
    static func upload(_ image: Data, hours: Int, server: String = server, token: String? = token) async throws -> URL {
        guard let token, !token.isEmpty, let request = request(image, hours: hours, server: server, token: token) else { throw Failure.notSetUp }
        let (data, response) = try await URLSession.shared.data(for: request)
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 201 else {
            throw Failure.rejected(answer?["error"] as? String ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard let link = (answer?["url"] as? String).flatMap(URL.init(string:)) else { throw Failure.noAnswer }
        return link
    }

    // MARK: Keychain

    private static let service = "app.apila.shots"

    static var token: String? {
        get {
            var item: CFTypeRef?
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecReturnData as String: true]
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
            SecItemDelete(query as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var add = query
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
