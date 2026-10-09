import Testing
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
        #expect(long == " one two three four five six seven eight")
        #expect(C.clean(" привіт, як справи", beforeCursor: "Ну") == " привіт, як справи")
    }

    @Test("Echoed last word: finishes a half word, or starts a new one with a space")
    func echo() {
        #expect(C.fromEcho("зручністю користування", beforeCursor: "Програма з") == "ручністю користування")
        #expect(C.fromEcho("з повною перевіркою", beforeCursor: "Тепер текст з") == " повною перевіркою")
        #expect(C.fromEcho("there, how are you?", beforeCursor: "Hello there") == ", how are you?")
        #expect(C.fromEcho("there how are you", beforeCursor: "Hello there ") == "how are you")
        #expect(C.fromEcho("«how are you»", beforeCursor: "Hello there") == " how are you")
        #expect(C.fromEcho("there\nmore", beforeCursor: "Hello there") == nil)
    }

    @Test("Going round in circles is cut off")
    func repeats() {
        #expect(C.fromEcho("з від тексту з від тексту з від тексту", beforeCursor: "перевіряю ввід тексту з") == " від")
        #expect(C.withoutRepeats(" a b c a b c", after: "x") == " a b c")
        #expect(C.withoutRepeats(" ввід тексту далі", after: "перевіряю ввід тексту") == "")
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
