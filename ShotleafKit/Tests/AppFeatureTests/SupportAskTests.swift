import Foundation
import Testing
@testable import AppFeature

@Test("The support ask comes after 50 shots, or a month with at least 10")
func supportAskDue() {
    let now = Date(), month = now.addingTimeInterval(-31 * 86_400)
    #expect(!SupportAsk.due(shots: 49, since: now, now: now))
    #expect(SupportAsk.due(shots: 50, since: now, now: now))
    #expect(!SupportAsk.due(shots: 9, since: month, now: now))
    #expect(SupportAsk.due(shots: 10, since: month, now: now))
}
