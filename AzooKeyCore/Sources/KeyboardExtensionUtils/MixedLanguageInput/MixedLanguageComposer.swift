//
//  MixedLanguageComposer.swift
//  AzooKeyCore
//

import KanaKanjiConverterModule

/// ローマ字入力中の`ComposingText`のうち、英語と判定した区間をダイレクト入力に切り替える。
///
/// 末尾に続けて打った英字（ローマ字入力、またはこの機能でダイレクト入力に切り替えた英字）を1つの「区間」とし、
/// 打つたびに区間全体を判定し直す。日本語の区間はローマ字入力のまま、英語の区間はダイレクト入力にする。
/// 例: `kyouhagoogledekensaku` → 変換対象 `きょうはgoogleでけんさく`
@MainActor
public enum MixedLanguageComposer {
    public struct Result {
        /// 書き換えた後の`ComposingText`。書き換えがなければ元のまま
        public var composingText: ComposingText
        /// 判定の対象にした区間の始まり（`input`の位置）。次に打ったときに使う
        public var runStartIndex: Int?
        /// 書き換えたか
        public var changed: Bool
    }

    /// 1度に判定する英字の数の上限。これより前の英字は今の入力方式のまま残す
    static let maxRunLength = 32

    /// - Parameters:
    ///   - composingText: 入力中の文字列
    ///   - runStartIndex: 前回の判定で返した区間の始まり。分からなければ`nil`
    ///   - segmenter: 判定に使う
    ///   - isFinal: 確定する直前の判定か
    ///   - precededByEnglish: 入力中の文字列の前（確定済みの文字）が英文か。区間が入力の先頭から始まるときだけ評価する
    public static func apply(
        to composingText: ComposingText,
        runStartIndex: Int?,
        segmenter: MixedLanguageSegmenter,
        isFinal: Bool,
        precededByEnglish: @autoclosure () -> Bool
    ) -> Result {
        let unchanged = Result(composingText: composingText, runStartIndex: nil, changed: false)
        guard composingText.isAtEndIndex, !composingText.input.isEmpty else {
            return unchanged
        }
        let input = composingText.input
        guard var start = Self.runStart(of: input, trackedStartIndex: runStartIndex) else {
            return unchanged
        }
        // 長すぎる区間は末尾だけを判定する
        if input.count - start > Self.maxRunLength {
            start = input.count - Self.maxRunLength
        }
        let letters = input[start...].compactMap(Self.letter(of:))
        let segments = segmenter.segment(letters, isFinal: isFinal, precededByEnglish: start == 0 && precededByEnglish())
        let newRun = Self.elements(letters: letters, segments: segments)

        let oldRun = Array(input[start...])
        if Self.isSame(oldRun, newRun) {
            return Result(composingText: composingText, runStartIndex: start, changed: false)
        }
        var newComposingText = ComposingText()
        newComposingText.insertAtCursorPosition(Array(input[..<start]) + newRun)
        return Result(composingText: newComposingText, runStartIndex: start, changed: true)
    }

    /// キャレットの前が英文の続き（`I want `のように、英語の語の後ろに空白がある）か
    public static func isEnglishSentenceContext(_ leftText: some StringProtocol) -> Bool {
        guard leftText.last == " " else {
            return false
        }
        let trimmed = leftText.reversed().drop(while: { $0 == " " })
        guard let last = trimmed.first, last.isASCII, last.isLetter || last.isNumber || ",.!?;:'\")".contains(last) else {
            return false
        }
        // 最後の語が英字を含み、ASCIIだけでできている
        let lastWord = trimmed.prefix(while: { !$0.isWhitespace })
        return lastWord.allSatisfy(\.isASCII) && lastWord.contains(where: RomajiSyllableCost.isLetter)
    }

    /// 英語の区間（ダイレクト入力の英字の並び）のうち固有名詞のものについて、打った綴りから正しい表記を引く表を作る（`iphone` → `iPhone`）
    public static func properNounSpellings(in composingText: ComposingText, checker: any EnglishWordChecking) -> [String: String] {
        var spellings: [String: String] = [:]
        var run = ""
        func flush() {
            if !run.isEmpty, let spelling = checker.properNounSpelling(run), spelling != run {
                spellings[run] = spelling
            }
            run = ""
        }
        for element in composingText.input {
            if element.inputStyle == .direct, let letter = Self.letter(of: element) {
                run.append(letter)
            } else {
                flush()
            }
        }
        flush()
        return spellings
    }

    /// `text`の中の英字の並び（前後が英字でないもの）のうち、`spellings`にあるものを置き換える
    public nonisolated static func replacingWords(in text: String, spellings: [String: String]) -> String {
        guard !spellings.isEmpty else {
            return text
        }
        var result = ""
        var run = ""
        func flush() {
            result.append(spellings[run] ?? run)
            run = ""
        }
        for character in text {
            if RomajiSyllableCost.isLetter(character) {
                run.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }

    /// `candidate`の英字の語を、固有名詞の正しい表記にした候補（`iphoneを買った` → `iPhoneを買った`）。置き換える語がなければ`nil`
    ///
    /// 大文字・小文字だけを変えるので文字数は変わらない。そのため、語（`data`）の区切りはそのまま使え、学習もできる。
    public nonisolated static func properNounCandidate(from candidate: Candidate, spellings: [String: String]) -> Candidate? {
        let text = Self.replacingWords(in: candidate.text, spellings: spellings)
        guard text != candidate.text, text.count == candidate.text.count else {
            return nil
        }
        var result = candidate
        result.text = text
        if candidate.data.map(\.word).joined() == candidate.text {
            var rest = text[...]
            result.data = candidate.data.map {
                var element = $0
                element.word = String(rest.prefix(element.word.count))
                rest = rest.dropFirst(element.word.count)
                return element
            }
        } else {
            // 語の区切りが表示と合わないときは、食い違った語を学習しない
            result.isLearningTarget = false
        }
        return result
    }

    /// 日英混在入力の変換候補を整える
    /// - 英単語の途中で切れる候補（`python`の`p`だけの候補）を除く
    /// - 英語の区間があれば、入力全体を変換した候補（ライブ変換が表示する候補）を先頭にする
    /// - 英語の区間が固有名詞なら、正しい表記にした候補（`iPhoneを買った`）を足す。
    ///   入力中の表示は打ったとおり（`iphoneを買った`）にし、正しい表記はそのすぐ後ろの候補にする
    public static func adjustingCandidates(_ result: ConversionResult, composingText: ComposingText, checker: any EnglishWordChecking) -> ConversionResult {
        var result = result
        let spellings = Self.properNounSpellings(in: composingText, checker: checker)
        result.mainResults = Self.adjustingMainResults(result.mainResults, composingText: composingText, spellings: spellings)
        result.firstClauseResults = Self.removingCandidatesSplittingWord(result.firstClauseResults, composingText: composingText)
        if !spellings.isEmpty {
            result.firstClauseResults = Self.insertingProperNounCandidate(into: result.firstClauseResults, spellings: spellings)
        }
        return result
    }

    /// `adjustingCandidates`のうち、候補一覧（`mainResults`）を整える部分
    /// - Parameter spellings: `properNounSpellings(in:checker:)`の結果
    nonisolated static func adjustingMainResults(_ candidates: [Candidate], composingText: ComposingText, spellings: [String: String]) -> [Candidate] {
        var candidates = Self.removingCandidatesSplittingWord(candidates, composingText: composingText)
        if composingText.input.contains(where: { $0.inputStyle == .direct && Self.letter(of: $0) != nil }) {
            candidates = Self.movingWholeInputCandidateToFront(candidates, convertTarget: composingText.convertTarget)
        }
        if !spellings.isEmpty {
            candidates = Self.insertingProperNounCandidate(into: candidates, spellings: spellings)
        }
        return candidates
    }

    /// 英字で終わり、残りの入力も英字で始まる候補（英単語の途中で切れる候補）を除く
    nonisolated static func removingCandidatesSplittingWord(_ candidates: [Candidate], composingText: ComposingText) -> [Candidate] {
        candidates.filter { candidate in
            guard let last = candidate.text.last, RomajiSyllableCost.isLetter(last) else {
                return true
            }
            var rest = composingText
            rest.prefixComplete(composingCount: candidate.composingCount)
            guard let next = rest.convertTarget.first else {
                return true
            }
            return !RomajiSyllableCost.isLetter(next)
        }
    }

    /// 読みが入力全体と同じ長さの最初の候補を先頭に移す。`LiveConversionManager`が入力中に表示するのもこの候補
    ///
    /// 変換器は、入力全体を変換した候補と予測候補（入力の先まで補う候補）を評価値の順に混ぜる。
    /// 英語の区間があると予測候補が先頭に来ることがあり（`kyouhaamazondekaimono` → `今日はamazonで買い物し`）、
    /// 入力中の表示と候補の先頭が食い違う。
    nonisolated static func movingWholeInputCandidateToFront(_ candidates: [Candidate], convertTarget: String) -> [Candidate] {
        let count = convertTarget.count
        guard let index = candidates.firstIndex(where: { $0.data.map(\.ruby).joined().count == count }), index > 0 else {
            return candidates
        }
        var result = candidates
        result.insert(result.remove(at: index), at: 0)
        return result
    }

    /// 固有名詞を含む最初の候補のすぐ後ろに、それを正しい表記にした候補を入れる
    nonisolated static func insertingProperNounCandidate(into candidates: [Candidate], spellings: [String: String]) -> [Candidate] {
        for (index, candidate) in candidates.enumerated() {
            guard let properNounCandidate = Self.properNounCandidate(from: candidate, spellings: spellings) else {
                continue
            }
            guard !candidates.contains(where: { $0.text == properNounCandidate.text }) else {
                return candidates
            }
            var result = candidates
            result.insert(properNounCandidate, at: index + 1)
            return result
        }
        return candidates
    }

    /// `Candidate.makePrefixClauseCandidate(data:)`と同じように、最初の文節の候補を作る。ただし、英単語の途中では区切らない
    ///
    /// ダイレクト入力の英字は1文字ずつ別の語になるので、そのままでは`python`の`p`だけが最初の文節になる。
    public nonisolated static func makePrefixClauseCandidate(data: some Collection<DicdataElement>) -> Candidate {
        var clause = Candidate.makePrefixClauseCandidate(data: data)
        var rest = data.dropFirst(clause.data.count)
        while let last = clause.text.last, RomajiSyllableCost.isLetter(last),
              let next = rest.first?.word.first, RomajiSyllableCost.isLetter(next) {
            let nextClause = Candidate.makePrefixClauseCandidate(data: rest)
            guard !nextClause.data.isEmpty else {
                break
            }
            let clauseData = clause.data + nextClause.data
            clause = Candidate(
                text: clause.text + nextClause.text,
                value: clause.value,
                composingCount: .surfaceCount(clauseData.reduce(0) { $0 + $1.ruby.count }),
                // 501は`makePrefixClauseCandidate`の初期値（語から決まらなかったとき）
                lastMid: nextClause.lastMid == 501 ? clause.lastMid : nextClause.lastMid,
                data: clauseData
            )
            rest = rest.dropFirst(nextClause.data.count)
        }
        return clause
    }

    /// 判定の対象にする区間の始まり
    static func runStart(of input: [ComposingText.InputElement], trackedStartIndex: Int?) -> Int? {
        // 前回の区間が今も英字だけで続いていれば、それを使う（この機能でダイレクト入力にした英字を含む）
        if let trackedStartIndex, trackedStartIndex < input.count,
           input[trackedStartIndex...].allSatisfy({ Self.letter(of: $0) != nil && ($0.inputStyle == .roman2kana || $0.inputStyle == .direct) }) {
            // 区間の前にローマ字入力の英字が続いていれば、それも含める
            var start = trackedStartIndex
            while start > 0, Self.isRomanLetter(input[start - 1]) {
                start -= 1
            }
            return start
        }
        // そうでなければ、末尾に続くローマ字入力の英字だけを対象にする
        var start = input.count
        while start > 0, Self.isRomanLetter(input[start - 1]) {
            start -= 1
        }
        return start < input.count ? start : nil
    }

    /// 判定の結果から、区間の入力要素を作る
    static func elements(letters: [Character], segments: [MixedLanguageSegment]) -> [ComposingText.InputElement] {
        var result: [ComposingText.InputElement] = []
        result.reserveCapacity(letters.count + 1)
        for (offset, segment) in segments.enumerated() {
            let part = letters[segment.range]
            switch segment.language {
            case .japanese:
                result.append(contentsOf: part.map { .init(character: $0, inputStyle: .roman2kana) })
                // 英語の直前の n は、区切りで「ん」にならずに英字のまま残るので、nn にして「ん」にする
                let nextIsEnglish = offset + 1 < segments.count && segments[offset + 1].language == .english
                let trailingN = part.reversed().prefix(while: { $0 == "n" }).count
                if nextIsEnglish && trailingN % 2 == 1 {
                    result.append(.init(character: "n", inputStyle: .roman2kana))
                }
            case .english:
                result.append(contentsOf: part.map { .init(character: $0, inputStyle: .direct) })
            }
        }
        return result
    }

    nonisolated static func letter(of element: ComposingText.InputElement) -> Character? {
        guard case let .character(character) = element.piece, RomajiSyllableCost.isLetter(character) else {
            return nil
        }
        return character
    }

    private static func isRomanLetter(_ element: ComposingText.InputElement) -> Bool {
        element.inputStyle == .roman2kana && Self.letter(of: element) != nil
    }

    private static func isSame(_ lhs: [ComposingText.InputElement], _ rhs: [ComposingText.InputElement]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.piece == $1.piece && $0.inputStyle == $1.inputStyle }
    }
}
