@testable import KeyboardExtensionUtils
import XCTest

@MainActor
final class MixedLanguageSegmenterTests: XCTestCase {
    /// OSのスペルチェッカーに頼らず、決まった英単語だけで判定する
    private func makeSegmenter() -> MixedLanguageSegmenter {
        MixedLanguageSegmenter(englishWordChecker: EnglishWordSetChecker(words: [
            "google", "googled", "ogle", "meeting", "want", "to", "go", "the", "park", "is", "ish",
            "apple", "python", "copy", "code", "tomato", "sake", "make", "ken", "thinking", "line",
            "sushi", "like", "mac", "at", "Tanaka", "GitHub", "hello", "world", "de", "no",
        ]))
    }

    /// 区間を「日本語は小文字のまま、英語は[ ]で囲む」形の文字列にする
    private func describe(_ input: String, isFinal: Bool = false, precededByEnglish: Bool = false) -> String {
        let letters = Array(input)
        let segments = self.makeSegmenter().segment(letters, isFinal: isFinal, precededByEnglish: precededByEnglish)
        return segments.map { segment in
            let text = String(letters[segment.range])
            return segment.language == .english ? "[\(text)]" : text
        }.joined()
    }

    func testJapaneseOnly() {
        XCTAssertEqual(describe("kensaku"), "kensaku")
        XCTAssertEqual(describe("konnichiha"), "konnichiha")
        XCTAssertEqual(describe("kyouhaiitenkidesune"), "kyouhaiitenkidesune")
        XCTAssertEqual(describe("fairu"), "fairu")
        XCTAssertEqual(describe("gakkou"), "gakkou")
        XCTAssertEqual(describe("nihongo"), "nihongo")
    }

    func testEnglishWordsReadableAsRomajiStayJapanese() {
        // ローマ字としても自然に読める語は日本語のまま
        XCTAssertEqual(describe("tomato"), "tomato")
        XCTAssertEqual(describe("sake"), "sake")
        XCTAssertEqual(describe("make"), "make")
        XCTAssertEqual(describe("code"), "code")
    }

    func testEnglishWordInJapaneseSentence() {
        XCTAssertEqual(describe("kyouhagoogledekensaku"), "kyouha[google]dekensaku")
        XCTAssertEqual(describe("ashitanomeetingwotsuika"), "ashitano[meeting]wotsuika")
        XCTAssertEqual(describe("watashihaapplegasuki"), "watashiha[apple]gasuki")
        XCTAssertEqual(describe("pythondekaku"), "[python]dekaku")
    }

    func testEnglishOnly() {
        XCTAssertEqual(describe("python"), "[python]")
        XCTAssertEqual(describe("apple"), "[apple]")
        XCTAssertEqual(describe("thinking"), "[thinking]")
        XCTAssertEqual(describe("helloworld"), "[helloworld]")
    }

    func testWhileTyping() {
        // 打っている途中は、続きを打てば日本語になる子音を日本語として待つ
        XCTAssertEqual(describe("kyouhagoog"), "kyouhagoog")
        // ローマ字として読めなくなったら、英単語の頭を英字にする
        XCTAssertEqual(describe("kyouhagoogl"), "kyouha[googl]")
        XCTAssertEqual(describe("kyouhagoogle"), "kyouha[google]")
        XCTAssertEqual(describe("kyouhagoogled"), "kyouha[googled]")
        XCTAssertEqual(describe("kyouhagooglede"), "kyouha[google]de")
        // 英単語の後に日本語を打てば、日本語に戻る
        XCTAssertEqual(describe("is"), "is")
        XCTAssertEqual(describe("isha"), "isha")
        XCTAssertEqual(describe("want"), "[want]")
        XCTAssertEqual(describe("wanta"), "wanta")
    }

    func testFinal() {
        // 確定するときは、末尾の子音は日本語にならない
        XCTAssertEqual(describe("ashitanomeeting", isFinal: false), "ashitanomeeting")
        XCTAssertEqual(describe("ashitanomeeting", isFinal: true), "ashitano[meeting]")
        XCTAssertEqual(describe("mac", isFinal: true), "[mac]")
        // 末尾の n は「ん」
        XCTAssertEqual(describe("ken", isFinal: true), "ken")
    }

    func testPrecededByEnglishSentence() {
        XCTAssertEqual(describe("to"), "to")
        XCTAssertEqual(describe("to", precededByEnglish: true), "[to]")
        XCTAssertEqual(describe("go", precededByEnglish: true), "[go]")
        XCTAssertEqual(describe("sushi", precededByEnglish: true), "[sushi]")
        // 英単語でなければ日本語
        XCTAssertEqual(describe("kyouha", precededByEnglish: true), "kyouha")
    }

    func testUppercase() {
        XCTAssertEqual(describe("I"), "[I]")
        XCTAssertEqual(describe("GitHubdekensaku"), "[GitHub]dekensaku")
        XCTAssertEqual(describe("Tanakasan"), "[Tanaka]san")
    }

    func testUnknownLettersKeepRomaji() {
        // 知らない英字の並びは、今までどおりローマ字入力のまま
        XCTAssertEqual(describe("nginx"), "nginx")
        XCTAssertEqual(describe("kyouhs", isFinal: true), "kyouhs")
    }

    private func describeWithProperNouns(_ input: String, isFinal: Bool = false) -> String {
        let segmenter = MixedLanguageSegmenter(englishWordChecker: EnglishWordSetChecker(
            words: ["phone", "book", "mac", "de", "no"],
            properNouns: ["iPhone", "Amazon", "Adobe", "Notion", "Siri", "MacBook"]
        ))
        let letters = Array(input)
        return segmenter.segment(letters, isFinal: isFinal).map { segment in
            let text = String(letters[segment.range])
            return segment.language == .english ? "[\(text)]" : text
        }.joined()
    }

    func testLowercaseProperNouns() {
        // スペルチェッカーは iPhone しか認めないが、同梱の辞書では小文字で引ける
        XCTAssertEqual(describeWithProperNouns("iphonewokatta", isFinal: true), "[iphone]wokatta")
        XCTAssertEqual(describeWithProperNouns("macbookgahoshii", isFinal: true), "[macbook]gahoshii")
    }

    func testReadableProperNounsAreEnglish() {
        // ローマ字として読める固有名詞（あまぞん、あどべ）も英語にする
        XCTAssertEqual(describeWithProperNouns("amazon"), "[amazon]")
        XCTAssertEqual(describeWithProperNouns("adobe"), "[adobe]")
        XCTAssertEqual(describeWithProperNouns("kyouhaamazondekaimono"), "kyouha[amazon]dekaimono")
        XCTAssertEqual(describeWithProperNouns("notionnimemosuru"), "[notion]nimemosuru")
        // 打っている途中は日本語のまま
        XCTAssertEqual(describeWithProperNouns("amazo"), "amazo")
    }

    func testJapaneseAroundProperNouns() {
        // 音節の途中から始まる並び（まどべ の adobe）は固有名詞にしない
        XCTAssertEqual(describeWithProperNouns("madobedeyomu", isFinal: true), "madobedeyomu")
        // 短い名前（しり）は、ローマ字として読めれば日本語のまま
        XCTAssertEqual(describeWithProperNouns("siri"), "siri")
        XCTAssertEqual(describeWithProperNouns("osiriwoutsu"), "osiriwoutsu")
    }
}
