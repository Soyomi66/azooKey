import KanaKanjiConverterModule
@testable import KeyboardExtensionUtils
import XCTest

@MainActor
final class MixedLanguageComposerTests: XCTestCase {
    private func makeSegmenter() -> MixedLanguageSegmenter {
        MixedLanguageSegmenter(englishWordChecker: EnglishWordSetChecker(words: [
            "google", "googled", "meeting", "want", "apple", "python",
        ]))
    }

    /// キーボードで1文字ずつ打つのと同じように、打つたびに判定する
    private func type(
        _ text: String,
        into composingText: inout ComposingText,
        runStartIndex: inout Int?,
        segmenter: MixedLanguageSegmenter
    ) {
        for character in text {
            composingText.insertAtCursorPosition(String(character), inputStyle: .roman2kana)
            let result = MixedLanguageComposer.apply(
                to: composingText,
                runStartIndex: runStartIndex,
                segmenter: segmenter,
                isFinal: false,
                precededByEnglish: false
            )
            composingText = result.composingText
            runStartIndex = result.runStartIndex
        }
    }

    private func convertTarget(typing text: String, isFinal: Bool = false) -> String {
        let segmenter = self.makeSegmenter()
        var composingText = ComposingText()
        var runStartIndex: Int?
        self.type(text, into: &composingText, runStartIndex: &runStartIndex, segmenter: segmenter)
        if isFinal {
            composingText = MixedLanguageComposer.apply(
                to: composingText,
                runStartIndex: runStartIndex,
                segmenter: segmenter,
                isFinal: true,
                precededByEnglish: false
            ).composingText
        }
        return composingText.convertTarget
    }

    func testMixedSentence() {
        XCTAssertEqual(convertTarget(typing: "kyouhagoogledekensaku"), "きょうはgoogleでけんさく")
        XCTAssertEqual(convertTarget(typing: "ashitanomeetingwotsuika"), "あしたのmeetingをついか")
        XCTAssertEqual(convertTarget(typing: "watashihaapplegasuki"), "わたしはappleがすき")
    }

    func testJapaneseOnlyIsUnchanged() {
        XCTAssertEqual(convertTarget(typing: "kyouhaiitenkidesune"), "きょうはいいてんきですね")
        XCTAssertEqual(convertTarget(typing: "gakkou"), "がっこう")
    }

    func testIntermediateState() {
        XCTAssertEqual(convertTarget(typing: "kyouhagoog"), "きょうはごおg")
        XCTAssertEqual(convertTarget(typing: "kyouhagoogl"), "きょうはgoogl")
        XCTAssertEqual(convertTarget(typing: "kyouhagoogle"), "きょうはgoogle")
    }

    func testFinal() {
        XCTAssertEqual(convertTarget(typing: "ashitanomeeting"), "あしたのめえちんg")
        XCTAssertEqual(convertTarget(typing: "ashitanomeeting", isFinal: true), "あしたのmeeting")
    }

    func testNBeforeEnglishBecomesN() {
        // 英語の直前の n は「ん」になる
        XCTAssertEqual(convertTarget(typing: "nihonpython"), "にほんpython")
    }

    func testDeleteAndRetype() {
        let segmenter = self.makeSegmenter()
        var composingText = ComposingText()
        var runStartIndex: Int?
        self.type("kyouhagoogle", into: &composingText, runStartIndex: &runStartIndex, segmenter: segmenter)
        XCTAssertEqual(composingText.convertTarget, "きょうはgoogle")
        // 英字を1文字消して打ち直しても、英語のまま
        composingText.deleteBackwardFromCursorPosition(count: 1)
        XCTAssertEqual(composingText.convertTarget, "きょうはgoogl")
        self.type("ede", into: &composingText, runStartIndex: &runStartIndex, segmenter: segmenter)
        XCTAssertEqual(composingText.convertTarget, "きょうはgoogleで")
    }

    func testCursorNotAtEndIsUntouched() {
        let segmenter = self.makeSegmenter()
        var composingText = ComposingText()
        composingText.insertAtCursorPosition("googleha", inputStyle: .roman2kana)
        _ = composingText.moveCursorFromCursorPosition(count: -1)
        let result = MixedLanguageComposer.apply(to: composingText, runStartIndex: nil, segmenter: segmenter, isFinal: false, precededByEnglish: false)
        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.composingText.convertTarget, composingText.convertTarget)
    }

    func testEnglishSentenceContext() {
        XCTAssertTrue(MixedLanguageComposer.isEnglishSentenceContext("I want "))
        XCTAssertTrue(MixedLanguageComposer.isEnglishSentenceContext("Hello, "))
        // 日本語の文の中の英単語の後ろは、英文の続きとして扱わない
        XCTAssertFalse(MixedLanguageComposer.isEnglishSentenceContext("今日はgoogle "))
        XCTAssertFalse(MixedLanguageComposer.isEnglishSentenceContext("I want"))
        XCTAssertFalse(MixedLanguageComposer.isEnglishSentenceContext("今日は "))
        XCTAssertFalse(MixedLanguageComposer.isEnglishSentenceContext("2026 "))
        XCTAssertFalse(MixedLanguageComposer.isEnglishSentenceContext(""))
    }

    func testDirectLettersBeforeRunAreKept() {
        // 英語入力で打った英字（この機能が切り替えたものではない）は、判定の対象にしない
        let segmenter = self.makeSegmenter()
        var composingText = ComposingText()
        composingText.insertAtCursorPosition("kyou", inputStyle: .direct)
        var runStartIndex: Int?
        self.type("ha", into: &composingText, runStartIndex: &runStartIndex, segmenter: segmenter)
        XCTAssertEqual(composingText.convertTarget, "kyouは")
    }

    func testProperNounSpellings() {
        let checker = EnglishWordSetChecker(words: ["phone"], properNouns: ["iPhone", "GitHub"])
        let segmenter = MixedLanguageSegmenter(englishWordChecker: checker)
        var composingText = ComposingText()
        var runStartIndex: Int?
        self.type("iphonetogithub", into: &composingText, runStartIndex: &runStartIndex, segmenter: segmenter)
        composingText = MixedLanguageComposer.apply(
            to: composingText,
            runStartIndex: runStartIndex,
            segmenter: segmenter,
            isFinal: true,
            precededByEnglish: false
        ).composingText
        XCTAssertEqual(composingText.convertTarget, "iphoneとgithub")
        XCTAssertEqual(MixedLanguageComposer.properNounSpellings(in: composingText, checker: checker), ["iphone": "iPhone", "github": "GitHub"])
    }

    func testReplacingOnlyWholeWords() {
        let spellings = ["iphone": "iPhone"]
        XCTAssertEqual(MixedLanguageComposer.replacingWords(in: "iphoneを買った", spellings: spellings), "iPhoneを買った")
        XCTAssertEqual(MixedLanguageComposer.replacingWords(in: "新しいiphoneとiphone", spellings: spellings), "新しいiPhoneとiPhone")
        // 英字の並びの一部は置き換えない
        XCTAssertEqual(MixedLanguageComposer.replacingWords(in: "iphones", spellings: spellings), "iphones")
    }

    /// 英字は1文字ずつ別の語にする（ダイレクト入力の英字の変換結果と同じ形）
    private func letterElements(_ text: String) -> [DicdataElement] {
        text.map { DicdataElement(word: String($0), ruby: String($0), cid: CIDData.一般名詞.cid, mid: MIDData.一般.mid, value: 0) }
    }

    func testProperNounCandidate() {
        let data = self.letterElements("iphone") + [DicdataElement(word: "を", ruby: "ヲ", cid: 0, mid: 0, value: 0)]
        let candidate = Candidate(text: "iphoneを", value: 0, composingCount: .inputCount(7), lastMid: 0, data: data)
        let result = MixedLanguageComposer.properNounCandidate(from: candidate, spellings: ["iphone": "iPhone"])
        XCTAssertEqual(result?.text, "iPhoneを")
        // 英字が複数の語に分かれていても、語の区切りを保って正しい表記にする
        XCTAssertEqual(result?.data.map(\.word), ["i", "P", "h", "o", "n", "e", "を"])
        // 置き換える語がなければ候補を作らない
        XCTAssertNil(MixedLanguageComposer.properNounCandidate(from: candidate, spellings: ["github": "GitHub"]))
    }

    func testInsertsProperNounCandidateAfterTypedForm() {
        let typed = Candidate(text: "iphone", value: 0, composingCount: .inputCount(6), lastMid: 0, data: self.letterElements("iphone"))
        let other = Candidate(text: "いphone", value: 0, composingCount: .inputCount(6), lastMid: 0, data: [])
        let result = MixedLanguageComposer.insertingProperNounCandidate(into: [typed, other], spellings: ["iphone": "iPhone"])
        XCTAssertEqual(result.map(\.text), ["iphone", "iPhone", "いphone"])
    }

    func testKeepsEnglishWordInFirstClause() {
        let data = self.letterElements("python") + [
            DicdataElement(word: "会議", ruby: "カイギ", cid: CIDData.一般名詞.cid, mid: MIDData.一般.mid, value: 0),
        ]
        // 変換器の関数は英字1文字で区切る
        XCTAssertEqual(Candidate.makePrefixClauseCandidate(data: data).text, "p")
        let clause = MixedLanguageComposer.makePrefixClauseCandidate(data: data)
        XCTAssertEqual(clause.text, "python")
        XCTAssertEqual(clause.data.map(\.word).joined(), clause.text)
        XCTAssertEqual(clause.composingCount, .surfaceCount(6))
        // 日本語で始まるときは変換器の関数と同じ
        let japanese = [DicdataElement(word: "今日", ruby: "キョウ", cid: CIDData.一般名詞.cid, mid: MIDData.一般.mid, value: 0)] + self.letterElements("python")
        XCTAssertEqual(MixedLanguageComposer.makePrefixClauseCandidate(data: japanese).text, Candidate.makePrefixClauseCandidate(data: japanese).text)
    }

    func testRemovesCandidatesSplittingWord() {
        var composingText = ComposingText()
        composingText.insertAtCursorPosition("python", inputStyle: .direct)
        composingText.insertAtCursorPosition("de", inputStyle: .roman2kana)
        let split = Candidate(text: "p", value: 0, composingCount: .surfaceCount(1), lastMid: 0, data: self.letterElements("p"))
        let whole = Candidate(text: "pythonで", value: 0, composingCount: .surfaceCount(7), lastMid: 0, data: self.letterElements("python"))
        XCTAssertEqual(MixedLanguageComposer.removingCandidatesSplittingWord([split, whole], composingText: composingText).map(\.text), ["pythonで"])
    }

    func testPutsWholeInputCandidateFirstWithEnglish() {
        // きょうはamazonでかいもの（15文字）
        var composingText = ComposingText()
        composingText.insertAtCursorPosition("kyouha", inputStyle: .roman2kana)
        composingText.insertAtCursorPosition("amazon", inputStyle: .direct)
        composingText.insertAtCursorPosition("dekaimono", inputStyle: .roman2kana)
        func element(_ word: String, _ ruby: String) -> DicdataElement {
            DicdataElement(word: word, ruby: ruby, cid: CIDData.一般名詞.cid, mid: MIDData.一般.mid, value: 0)
        }
        let head = [element("今日", "キョウ"), element("は", "ハ")] + self.letterElements("amazon") + [element("で", "デ")]
        // 予測候補は入力の先（し）まで読みに含む
        let prediction = Candidate(text: "今日はamazonで買い物し", value: -10, composingCount: .surfaceCount(15), lastMid: 0, data: head + [element("買い物し", "カイモノシ")])
        let whole = Candidate(text: "今日はamazonで買い物", value: -20, composingCount: .surfaceCount(15), lastMid: 0, data: head + [element("買い物", "カイモノ")])
        let checker = EnglishWordSetChecker(words: ["amazon"], properNouns: ["Amazon"])
        let result = MixedLanguageComposer.adjustingMainResults(
            [prediction, whole],
            composingText: composingText,
            spellings: MixedLanguageComposer.properNounSpellings(in: composingText, checker: checker)
        )
        // 正しい表記の候補も、入力全体を変換した候補から作る
        XCTAssertEqual(result.map(\.text), ["今日はamazonで買い物", "今日はAmazonで買い物", "今日はamazonで買い物し"])
    }

    func testKeepsOrderWithoutEnglish() {
        var composingText = ComposingText()
        composingText.insertAtCursorPosition("kaimono", inputStyle: .roman2kana)
        let prediction = Candidate(text: "買い物し", value: -10, composingCount: .surfaceCount(4), lastMid: 0, data: [DicdataElement(word: "買い物し", ruby: "カイモノシ", cid: 0, mid: 0, value: 0)])
        let whole = Candidate(text: "買い物", value: -20, composingCount: .surfaceCount(4), lastMid: 0, data: [DicdataElement(word: "買い物", ruby: "カイモノ", cid: 0, mid: 0, value: 0)])
        let result = MixedLanguageComposer.adjustingMainResults([prediction, whole], composingText: composingText, spellings: [:])
        // 英語の区間がなければ、変換器の並びのまま
        XCTAssertEqual(result.map(\.text), ["買い物し", "買い物"])
    }

    func testSystemCheckerUsesBuiltInWords() {
        // 同梱の辞書は小文字で引く
        let checker = SystemEnglishWordChecker()
        XCTAssertTrue(checker.isEnglishWord("iphone"))
        XCTAssertTrue(checker.isEnglishWord("github"))
        XCTAssertTrue(checker.hasEnglishWord(withPrefix: "iph"))
        XCTAssertEqual(checker.properNounSpelling("iphone"), "iPhone")
        XCTAssertEqual(checker.properNounSpelling("macbook"), "MacBook")
        XCTAssertNil(checker.properNounSpelling("kyouha"))
    }
}
