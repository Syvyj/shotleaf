import Testing
import Foundation
@testable import AppFeature

@Suite("Inline completion text")
struct CompletionTextTests {
    typealias C = CompletionText

    @Test("Prompt: the end of the text, trailing spaces dropped")
    func prompt() {
        #expect(C.prompt(beforeCursor: "Hello there  ") == "Hello there")
        #expect(C.prompt(beforeCursor: String(repeating: "a", count: 5000)).count == C.contextLimit)
    }

    @Test("Clean: one line, no doubled space, at most maxWords words")
    func clean() {
        #expect(C.clean(" world, how are you\nNext line", beforeCursor: "Hello") == " world, how are you")
        #expect(C.clean(" world", beforeCursor: "Hello ") == "world")
        #expect(C.clean("   \n", beforeCursor: "Hello") == nil)
        let long = C.clean(" one two three four five six seven eight nine ten", beforeCursor: "x")
        #expect(long == " one two three four five six")
        #expect(C.clean(" привіт, як справи", beforeCursor: "Ну") == " привіт, як справи")
    }

    @Test("Continuation: finishes a half word, starts a new one, one line")
    func continuation() {
        #expect(C.suggestion(fromContinuation: "ручністю користування", beforeCursor: "Програма з") == "ручністю користування")
        #expect(C.suggestion(fromContinuation: " повною перевіркою\nдалі", beforeCursor: "Тепер текст з") == " повною перевіркою")
        #expect(C.suggestion(fromContinuation: " how are you", beforeCursor: "Hello there ") == "how are you")
        #expect(C.suggestion(fromContinuation: "\nmore", beforeCursor: "Hello") == nil)
    }

    @Test("Unsure or unfinished: whole words only, one sentence at most")
    func cutOff() {
        #expect(C.suggestion(fromContinuation: " повною перевір", finished: false, beforeCursor: "текст з") == " повною")
        #expect(C.suggestion(fromContinuation: " пов", finished: false, beforeCursor: "текст з") == nil)
        #expect(C.suggestion(fromContinuation: "ручніс", finished: false, beforeCursor: "Програма з") == "ручніс")
        #expect(C.suggestion(fromContinuation: " is done. Then we", finished: false, beforeCursor: "It") == " is done.")
        #expect(C.suggestion(fromContinuation: " see you", finished: true, beforeCursor: "Ok,") == " see you")
    }

    @Test("Going round in circles is cut off")
    func repeats() {
        #expect(C.suggestion(fromContinuation: " від тексту з від тексту з", beforeCursor: "перевіряю ввід тексту з") == " від")
        #expect(C.withoutRepeats(" a b c a b c", after: "x") == " a b c")
        #expect(C.withoutRepeats(" ввід тексту далі", after: "перевіряю ввід тексту") == "")
    }

    @Test("Context: labelled notes, then a rule, then the user's text last")
    func contextPrompt() {
        let context = C.Context(app: "Telegram", window: "Олег", screen: "Олег: їдемо завтра?\nНу то що, я думаю", clipboard: "вул. Хрещатик, 1")
        let p = C.prompt(beforeCursor: "Ну то що, я думаю ", context: context)
        #expect(p.hasPrefix("App: Telegram — Олег\n\nOn screen:\nОлег: їдемо завтра?\n\nJust copied:\nвул. Хрещатик, 1"))
        #expect(p.hasSuffix("\n\n---\n\nНу то що, я думаю"))
        #expect(!p.contains("On screen:\nОлег: їдемо завтра?\nНу то що")) // the field's own line is left out
        #expect(C.prompt(beforeCursor: "Hello there", context: C.Context()) == "Hello there")
    }

    @Test("Invisible characters after the cursor don't make it mid-text")
    func restOfLine() {
        #expect(C.restOfLine("\u{200B}") == "")
        #expect(C.restOfLine("\u{FFFC}\u{FEFF} ") == "")
        #expect(C.restOfLine(" at ten.\nnext line") == " at ten.")
        #expect(C.restOfLine("\nnext line") == "")
    }

    @Test("Tab takes the next word with its spaces and punctuation")
    func nextWord() {
        #expect(C.nextWord(of: " world, how are you") == (" world,", " how are you"))
        #expect(C.nextWord(of: "you") == ("you", ""))
    }

    @Test("Typing the suggested letters keeps the rest; anything else drops it")
    func advance() {
        #expect(C.advance(" world", typed: " ") == "world")
        #expect(C.advance("world", typed: "wo") == "rld")
        #expect(C.advance("world", typed: "x") == nil)
        #expect(C.advance("world", typed: "world") == nil)
    }

    @Test("Too little text, or a fresh line, asks nothing")
    func shouldComplete() {
        #expect(!C.shouldComplete(beforeCursor: "Hi"))
        #expect(!C.shouldComplete(beforeCursor: "Hello\n"))
        #expect(C.shouldComplete(beforeCursor: "Hello wor"))
    }
}

@Suite("Quick fixes & boldness")
@MainActor
struct QuickFixTests {
    @Test("Emoji picker: : or ; opens it, letters filter by Unicode names, recents when empty")
    func emoji() {
        #expect(EmojiShortcodes.query(beforeCursor: "We shipped it :") == "")
        #expect(EmojiShortcodes.query(beforeCursor: "We shipped it ;Roc") == "roc")
        #expect(EmojiShortcodes.query(beforeCursor: ":") == "")
        #expect(EmojiShortcodes.query(beforeCursor: "time 10:30") == nil)   // not after a space
        #expect(EmojiShortcodes.query(beforeCursor: "smile :-)") == nil)
        #expect(EmojiShortcodes.query(beforeCursor: "so :fire ") == nil)    // finished with a space
        #expect(EmojiShortcodes.candidates("rocke", recents: []).first?.emoji == "🚀")
        #expect(EmojiShortcodes.candidates("rock", recents: []).first?.emoji == "🪨") // the exact name first
        #expect(EmojiShortcodes.candidates("fire", recents: []).first?.emoji == "🔥")
        #expect(EmojiShortcodes.candidates("up", recents: []).contains { $0.name.contains("thumbs_up") }) // a word inside
        #expect(EmojiShortcodes.candidates("", recents: ["🚀", "👍"]).map(\.emoji) == ["🚀", "👍"])
        #expect(EmojiShortcodes.candidates("e", recents: []).count == 8)
    }

    @Test("A misspelled word just finished gets a fix that replaces it and the space")
    func typo() {
        let fix = TypoFixer.fix(beforeCursor: "I think we shoud ")
        #expect(fix == .typo("should ", replacing: 6))
        #expect(TypoFixer.fix(beforeCursor: "I think we should ") == nil)
        #expect(TypoFixer.fix(beforeCursor: "I think we shoud") == nil) // still typing it
    }

    @Test("Boldness: cautious asks more of the model and stops sooner")
    func boldness() {
        let cautious = CompletionText.Boldness(0), bold = CompletionText.Boldness(1)
        #expect(cautious.minTokenProbability > bold.minTokenProbability)
        #expect(cautious.maxWords == 3 && bold.maxWords == 9 && CompletionText.Boldness(0.5).maxWords == 6)
    }

    @Test("Mid-text: the suggestion stops before the words already after the cursor; style examples go first")
    func midText() {
        #expect(CompletionText.suggestion(fromContinuation: " on Friday morning at ten", beforeCursor: "See you", afterCursor: "at ten.")
                == " on Friday morning")
        #expect(CompletionText.suggestion(fromContinuation: " at ten", beforeCursor: "See you", afterCursor: "at ten.") == nil)
        #expect(CompletionText.suggestion(fromContinuation: "!", beforeCursor: "See you on Friday", afterCursor: " at ten.") == nil)
        let p = CompletionText.prompt(beforeCursor: "Hey", context: .init(examples: ["Cheers, talk soon!"]))
        #expect(p.hasPrefix("Earlier by the same writer:\n- Cheers, talk soon!"))
    }
}

@Suite("Writing history")
@MainActor
struct WritingHistoryTests {
    @Test("Remembers finished texts per app, offers the newest two, survives a restart, forgets")
    func history() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shotleaf-history-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let h = WritingHistory(url: url)
        h.remember("short", app: "tg")                                         // too short
        h.remember("Привіт! Так, давай о третій біля офісу, я буду трохи раніше.", app: "tg")
        h.remember("Дякую, отримав. Подивлюсь сьогодні ввечері й відпишу тобі.", app: "tg")
        h.remember("Hi Mark, thanks — I'll send the report by Friday.", app: "mail")
        #expect(h.examples(for: "tg", current: "Ок").first?.hasPrefix("Дякую") == true)
        #expect(h.examples(for: "tg", current: "Ок").count == 2)
        #expect(h.examples(for: "mail", current: "Hi Mark, thanks — I'll send").isEmpty) // the one being written
        #expect(WritingHistory(url: url).examples(for: "tg", current: "").count == 2)    // saved to disk
        h.forget()
        #expect(h.isEmpty && WritingHistory(url: url).isEmpty)
    }
}

@Suite("Context emoji")
struct ContextEmojiTests {
    @Test("Parses the model's emoji line; fitting ones first, then recents, no repeats")
    func parse() {
        #expect(ContextEmoji.parse(" 🎉🎂 🥳🎉\nMessage: x 😀") == ["🎉", "🎂", "🥳"])
        #expect(ContextEmoji.parse(" ❤️ 1 # 👍🏽") == ["❤️", "👍🏽"])
        #expect(ContextEmoji.merged(["🎉", "👍"], recents: ["👍", "😂", "❤️"], limit: 4) == ["🎉", "👍", "😂", "❤️"])
        #expect(ContextEmoji.prompt(for: "Вітаю з днем народження").hasSuffix("Message: Вітаю з днем народження\nEmoji:"))
    }
}
