import Testing
@testable import AppFeature

@Test("Versions compare by number, not as text")
func updateVersions() {
    #expect(Updates.isNewer("0.10.0", than: "0.9.1"))
    #expect(Updates.isNewer("v0.2", than: "0.1.9"))
    #expect(!Updates.isNewer("0.1.0", than: "0.1"))
    #expect(!Updates.isNewer("0.1.0", than: "0.2.0"))
}

@Test("The checksum file gives its SHA-256, anything else gives nothing")
func updateChecksum() {
    let hex = String(repeating: "ab", count: 32)
    #expect(Updates.checksum(in: "\(hex.uppercased())  Shotleaf.dmg\n") == hex)
    #expect(Updates.checksum(in: "not a checksum") == nil)
    #expect(Updates.checksum(in: "") == nil)
}
