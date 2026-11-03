import Testing
import AppKit
@testable import AppFeature

@Suite("Blur private info")
@MainActor
struct PrivateSpotsTests {
    @Test("Emails, phones, cards and tokens are found in a line; plain words are not")
    func ranges() {
        let parts = { (line: String) in PrivateSpots.ranges(in: line).map { String(line[$0]) } }
        #expect(parts("Write to anna.k@example.com today") == ["anna.k@example.com"])
        #expect(parts("Call +380 67 123 4567").count == 1)
        #expect(parts("Card 4242 4242 4242 4242 exp 12/29").contains("4242 4242 4242 4242"))
        #expect(parts("key ghp_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8").contains { $0.hasPrefix("ghp_") })
        #expect(parts("Meeting notes for Tuesday, room 4").isEmpty)
    }

    // On GitHub's runners (a VM without the GPU) Vision's face request never returns and stalls the whole run.
    @Test("Vision finds the email on a picture, where it is", .disabled(if: ProcessInfo.processInfo.environment["CI"] != nil))
    func onPicture() async throws {
        let size = CGSize(width: 800, height: 200)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.white.setFill(); rect.fill()
            ("Contact: anna.k@example.com" as NSString).draw(at: CGPoint(x: 40, y: 80),
                withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
            return true
        }
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let spots = await PrivateSpots.find(in: cg, size: size)
        let spot = try #require(spots.first)
        #expect(spots.count == 1)
        #expect(spot.minX > 100 && spot.minY > 60 && spot.maxY < 140) // the address, not "Contact:"
    }
}
