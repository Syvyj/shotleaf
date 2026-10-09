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
    ]

    public static func run() async {
        let model = EmbeddedModel.completion
        guard model.isDownloaded else { print("completion model not downloaded"); return }
        _ = try? await model.complete("warm up")
        for (before, context) in samples {
            let prompt = CompletionText.prompt(beforeCursor: before, context: context)
            let started = ContinuousClock.now
            let tokens = TokenLog()
            let result = try? await model.complete(prompt, trace: { piece, p in tokens.add(piece, p) })
            let took = ContinuousClock.now - started
            print("=== \(before.debugDescription)  context: \(context.screen != nil)  prompt \(prompt.count) chars  \(took)")
            print("    " + tokens.items.map { "\($0.0.debugDescription)@\(String(format: "%.2f", $0.1))" }.joined(separator: " "))
            let shown = result.flatMap { CompletionText.suggestion(fromContinuation: $0.text, finished: $0.finished, beforeCursor: before) }
            print("    raw: \((result?.text ?? "nil").debugDescription)  shown: \((shown ?? "nil").debugDescription)")
        }
    }

    private final class TokenLog: @unchecked Sendable {
        private(set) var items: [(String, Float)] = []
        func add(_ piece: String, _ p: Float) { items.append((piece, p)) }
    }
}
