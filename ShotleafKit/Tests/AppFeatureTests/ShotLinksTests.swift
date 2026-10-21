import Testing
import Foundation
@testable import AppFeature

@Suite("Screenshot links")
struct ShotLinksTests {
    @Test("Only https (http just for this Mac); the upload goes to /upload with the key and the time")
    func request() throws {
        #expect(ShotLinks.endpoint("https://shot.example.com")?.absoluteString == "https://shot.example.com/upload")
        #expect(ShotLinks.endpoint("https://example.com/shots/")?.absoluteString == "https://example.com/shots/upload")
        #expect(ShotLinks.endpoint("http://shot.example.com") == nil)
        #expect(ShotLinks.endpoint("http://127.0.0.1:8787") != nil)
        #expect(ShotLinks.endpoint("shot.example.com") == nil)
        let r = try #require(ShotLinks.request(Data([1]), hours: 6, server: "https://shot.example.com", token: "k"))
        #expect(r.url?.absoluteString == "https://shot.example.com/upload?ttl=21600")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer k" && r.httpMethod == "POST")
        // The free service: no key sent, links up to 12 hours.
        let free = try #require(ShotLinks.request(Data([1]), hours: 12, server: ShotLinks.freeService, token: nil))
        #expect(free.url?.absoluteString == "https://s.syvyj.dev/upload?ttl=43200")
        #expect(free.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(ShotLinks.choices.max() == 12)
    }

    @Test("End to end with server/shots/shots.py running on this Mac")
    func endToEnd() async throws {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../server/shots/shots.py").standardized
        guard FileManager.default.fileExists(atPath: "/usr/bin/python3"), FileManager.default.fileExists(atPath: script.path) else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotleaf-links-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [script.path]
        server.environment = ["SHOTS_TOKEN": "test-key", "SHOTS_DIR": dir.path, "SHOTS_PORT": "8797"]
        server.standardOutput = FileHandle.nullDevice
        try server.run()
        defer { server.terminate() }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        // Python takes a moment to listen (longer on a CI runner): retry while the connection is refused.
        var found: URL?
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(250))
            do { found = try await ShotLinks.upload(png, hours: 1, server: "http://127.0.0.1:8797", token: "test-key"); break }
            catch let error as URLError where error.code == .cannotConnectToHost { continue }
        }
        let link = try #require(found)
        let (body, response) = try await URLSession.shared.data(from: link)
        #expect((response as? HTTPURLResponse)?.statusCode == 200 && body == png)
        await #expect(throws: ShotLinks.Failure.self) {
            try await ShotLinks.upload(png, hours: 1, server: "http://127.0.0.1:8797", token: "wrong")
        }
    }
}
