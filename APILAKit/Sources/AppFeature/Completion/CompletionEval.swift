import EmbeddedKit
import Foundation

/// Developer run: `APILA --completion-eval` puts fixed samples (not the
/// user's text) through the completion model and prints each token with the
/// model's confidence, the time, and what would be shown — to tune the
/// prompt and thresholds without guessing.
public enum CompletionEval {
    static let samples: [(String, CompletionText.Context)] = [
        ("Привіт, я перевіряю ввід тексту з", .init()),
        ("Добрий день! Дякую за ваш лист. Щодо зустрічі в четвер, я", .init()),
        ("Слухай, а ти завтра будеш на", .init()),
        ("Hi Anna, thanks for the update. I think we should", .init()),
        ("Привіт! Так, я ", .init(app: "Telegram", window: "Олег",
                                  screen: "Олег\nПривіт! Ти сьогодні на каву підеш?\nО 15:00 біля офісу, як завжди", clipboard: nil)),
        ("Hi Mark, sure, I can send it ", .init(app: "Mail", window: "Re: Q3 report",
                                                 screen: "From: Mark\nCould you send me the Q3 report by Friday? Thanks!", clipboard: nil)),
        // Live-sized: a long note plus a screenful of text.
        (String(repeating: "Сьогодні ми обговорили план на квартал, бюджет і найм нових людей у команду. ", count: 18)
            + "Наступного тижня я", .init(app: "Notes", window: "Нотатки",
                                         screen: String(repeating: "Зустріч з командою о 10:00, звіт до п'ятниці, бюджет на рекламу. ", count: 10),
                                         clipboard: nil)),
    ]

    public static func run() async {
        let model = EmbeddedModel.completion
        guard model.isDownloaded else { print("completion model not downloaded"); return }
        _ = try? await model.complete("warm up")
        let sweep: [(String, CompletionText.Context)] = [2, 4, 6, 8, 10, 12, 16, 20, 26].map { n in
            (String(repeating: "Сьогодні ми обговорили план на квартал і бюджет. ", count: n) + "Наступного тижня я", CompletionText.Context())
        }
        // Typing: the same long note, a few more letters each time.
        let note = String(repeating: "Сьогодні ми обговорили план на квартал і бюджет. ", count: 10) + "Наступного тижня я хочу"
        let typing: [(String, CompletionText.Context)] = [0, 2, 5, 9, 12].map { n in
            (note + String(" поговорити з командою".prefix(n)), CompletionText.Context())
        }
        for (before, context) in samples + sweep + typing {
            let prompt = before.count > 300 && context.screen == nil ? before : CompletionText.prompt(beforeCursor: before, context: context)
            let started = ContinuousClock.now
            let tokens = TokenLog(started: started)
            let result = try? await model.complete(prompt, trace: { piece, p in tokens.add(piece, p) })
            let took = ContinuousClock.now - started
            print("=== first token \(tokens.firstAt.map { "\($0 - started)" } ?? "-")  \(String(before.suffix(40)).debugDescription)  context: \(context.screen != nil)  prompt \(prompt.count) chars  \(took)")
            print("    " + tokens.items.map { "\($0.0.debugDescription)@\(String(format: "%.2f", $0.1))" }.joined(separator: " "))
            let shown = result.flatMap { CompletionText.suggestion(fromContinuation: $0.text, finished: $0.finished, beforeCursor: before) }
            print("    reused \(await model.lastReusedTokens) tokens")
            print("    raw: \((result?.text ?? "nil").debugDescription)  shown: \((shown ?? "nil").debugDescription)")
        }
    }

    private final class TokenLog: @unchecked Sendable {
        let started: ContinuousClock.Instant
        private(set) var items: [(String, Float)] = []
        private(set) var firstAt: ContinuousClock.Instant?
        init(started: ContinuousClock.Instant) { self.started = started }
        func add(_ piece: String, _ p: Float) {
            if firstAt == nil { firstAt = .now }
            items.append((piece, p))
        }
    }
}
