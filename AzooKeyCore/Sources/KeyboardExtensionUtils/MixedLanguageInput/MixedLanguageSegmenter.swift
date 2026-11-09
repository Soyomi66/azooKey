//
//  MixedLanguageSegmenter.swift
//  AzooKeyCore
//
//  ローマ字入力中に打った英字の並びを、日本語（ローマ字）の区間と英語の区間に分ける。
//  例: `kyouhagoogledekensaku` → `kyouha`(日本語) `google`(英語) `dekensaku`(日本語)
//
//  考え方
//  - 英字の各位置を区切りの候補にし、「日本語の音節」「英単語」をノードにしたラティスを作る。
//  - 各ノードと、日本語と英語の切り替えにコストを付け、合計が最小になる区切りを Viterbi で選ぶ。
//  - 日本語のローマ字として自然に読める区間はコストが 0 になるので、英単語の候補があっても日本語を選ぶ。
//    英語になるのは、ローマ字としては読みにくい区間（`gl` のように母音のない子音、`gwo` のようにまず打たない音節）を
//    英単語が覆うときだけ。そのため、`tomato` や `sake` のように両方に読める語は日本語のまま。
//  - ただし、同梱の辞書に載せた5文字以上の固有名詞（`amazon`、`adobe`）は、ローマ字として読めても英語にする。
//    4文字以下の固有名詞（`java`）は日本語の語と重なりやすいので、ほかの英単語と同じように、ローマ字として読めれば日本語のままにする。
//

/// 英字の並びの一部と、その言語
public struct MixedLanguageSegment: Equatable, Sendable {
    public enum Language: Equatable, Sendable {
        case japanese
        case english
    }

    public var range: Range<Int>
    public var language: Language

    public init(range: Range<Int>, language: Language) {
        self.range = range
        self.language = language
    }
}

@MainActor
public struct MixedLanguageSegmenter {
    public init(englishWordChecker: any EnglishWordChecking) {
        self.englishWordChecker = englishWordChecker
    }

    private let englishWordChecker: any EnglishWordChecking

    /// 1つの英単語として調べる長さの上限
    static let maxEnglishWordLength = 24
    /// ローマ字として読めても英語にする固有名詞の長さの下限
    static let minProperNounLength = 5

    /// ノードと連接のコスト
    enum Cost {
        // ---- 日本語のノード ----
        /// 入力の末尾にある、音節の途中まで打った子音（`k`、`ky`）。続きを打てば日本語になる
        static let pendingConsonant: Double = 1.2
        /// どの音節にもならない子音（`google` の `g`）。かなにならずに英字のまま残る
        static let danglingLetter: Double = 3.0

        // ---- 英語のノード ----
        /// 英単語。長い語ほど偶然ローマ字の並びと重なることが少ないので、軽くする
        static func englishWord(length: Int) -> Double {
            max(0.6, 1.5 - 0.1 * Double(length))
        }
        /// 1文字の英単語「I」
        static let singleLetterI: Double = 1.0
        /// 大文字1文字（知らない語の頭字など）
        static let singleUppercase: Double = 1.5
        /// 大文字で始まる知らない語（`Tanaka`、`McKinsey`）。日本語の音節は大文字を含まないので英字のままにする
        static func capitalizedName(length: Int) -> Double {
            1.0 + 0.15 * Double(length - 1)
        }
        /// 同梱の辞書に載せた5文字以上の固有名詞（`amazon`）。
        /// 日本語の中に置いても（切り替え 0.5 ＋ 英語の後の日本語 0.5）、ローマ字で読んだとき（0）より小さくなるようにする
        static let properNoun: Double = -1.5
        /// 入力の末尾にある、英単語の頭（`googl`）
        static let englishPrefix: Double = 1.8
        /// 確定するときの、英単語の頭
        static let englishPrefixAtFinal: Double = 2.5
        /// 固有名詞を除いた、英語ノードの最小コスト。日本語だけで読んだときのコストがこれより小さければ、英語を調べない
        static let minimumEnglishNode: Double = 0.6
        /// 同じコストなら日本語を選ぶ
        static let englishTieBreak: Double = 1e-6

        // ---- 連接 ----
        /// 日本語から英語への切り替え
        static let japaneseToEnglish: Double = 0.5
        /// 英語から日本語への切り替え
        static let englishToJapanese: Double = 0.5
        /// 英語から、名詞に付く語（で、を、する、さん など）への切り替え
        static let englishToAttachedWord: Double = 0.25
        /// 子音で終わる英語のすぐ後ろが母音で始まる日本語（`googled|e`）。英単語の最後の子音の切り間違い
        static let vowelAfterEnglish: Double = 1.0
        /// 英単語どうしが区切りなしに続く
        static let englishToEnglish: Double = 0.5
        /// キャレットの前が英文のときに、日本語から始める
        static let japaneseAfterEnglishSentence: Double = 1.5
    }

    /// 英語のすぐ後ろに続きやすい日本語の語（助詞・助動詞・する・敬称）のローマ字
    static let attachedWords: [String] = [
        "de", "ga", "wo", "ni", "no", "ha", "wa", "mo", "to", "he", "ya",
        "kara", "made", "yori", "dake", "desu", "da", "na",
        "suru", "shi", "si", "tte",
        "san", "kun", "chan", "sama",
    ]

    /// 英字の並びを日本語と英語の区間に分ける。
    /// - Parameters:
    ///   - letters: 打った英字（`a`〜`z`、`A`〜`Z`）
    ///   - isFinal: 確定する直前の判定か。`false`のときは、末尾の子音を続きを打つ途中として扱う
    ///   - precededByEnglish: キャレットの前が英文（`I want `など）か
    /// - Returns: 先頭から順に並んだ区間。隣り合う区間の言語は異なる
    public func segment(_ letters: [Character], isFinal: Bool, precededByEnglish: Bool = false) -> [MixedLanguageSegment] {
        let count = letters.count
        guard count > 0 else {
            return []
        }
        let lowercased = letters.map { Character($0.lowercased()) }
        let japaneseTokens = (0 ..< count).map { Self.japaneseTokens(lowercased: lowercased, original: letters, at: $0, isFinal: isFinal) }

        // 日本語だけで十分自然に読めるなら、英語を調べずに日本語にする（固有名詞があるときは調べる）
        if !precededByEnglish,
           !self.containsProperNoun(letters),
           let japaneseOnlyCost = Self.japaneseOnlyCost(tokens: japaneseTokens, count: count),
           japaneseOnlyCost < Cost.minimumEnglishNode {
            return [.init(range: 0 ..< count, language: .japanese)]
        }

        let englishNodes = (0 ..< count).map { self.englishNodes(letters: letters, at: $0, isFinal: isFinal) }
        return Self.bestPath(
            letters: letters,
            japaneseTokens: japaneseTokens,
            englishNodes: englishNodes,
            precededByEnglish: precededByEnglish
        )
    }

    // MARK: - ノード

    /// ノードの終わりの位置とコスト
    struct Node: Equatable {
        var end: Int
        var cost: Double
    }

    /// `index`から始まる日本語の音節
    static func japaneseTokens(lowercased: [Character], original: [Character], at index: Int, isFinal: Bool) -> [Node] {
        let count = lowercased.count
        let first = original[index]
        // 大文字は日本語の音節にしない
        guard !RomajiSyllableCost.isUppercaseLetter(first) else {
            return []
        }
        var nodes: [Node] = []
        // 通常の音節
        var key = ""
        for end in index + 1 ... min(count, index + RomajiSyllableCost.maxSyllableLength) {
            let character = original[end - 1]
            if RomajiSyllableCost.isUppercaseLetter(character) {
                break
            }
            key.append(lowercased[end - 1])
            if let cost = RomajiSyllableCost.table[key] {
                nodes.append(.init(end: end, cost: cost))
            }
        }
        let current = lowercased[index]
        let next: Character? = index + 1 < count ? lowercased[index + 1] : nil
        // ん: 母音・y・n以外の前のn、または末尾のn
        if current == "n" {
            if let next {
                if !RomajiSyllableCost.isVowel(next) && next != "y" && next != "n" {
                    nodes.append(.init(end: index + 1, cost: RomajiSyllableCost.common))
                }
            } else {
                nodes.append(.init(end: index + 1, cost: RomajiSyllableCost.common))
            }
        }
        // っ: 同じ子音を重ねる
        if let next, next == current, !RomajiSyllableCost.isVowel(current), current != "n",
           RomajiSyllableCost.isLowercaseLetter(current), !RomajiSyllableCost.isUppercaseLetter(original[index + 1]) {
            nodes.append(.init(end: index + 1, cost: RomajiSyllableCost.sokuon(current)))
        }
        // 入力の末尾の、音節の途中まで打った子音
        if !isFinal, count - index <= RomajiSyllableCost.maxSyllableLength - 1, current != "n" {
            let rest = String(lowercased[index...])
            let restHasUppercase = original[index...].contains(where: RomajiSyllableCost.isUppercaseLetter)
            if !restHasUppercase, RomajiSyllableCost.pendingPrefixes.contains(rest) {
                nodes.append(.init(end: count, cost: Cost.pendingConsonant))
            }
        }
        // どの音節にもならない英字は、そのまま残る
        nodes.append(.init(end: index + 1, cost: Cost.danglingLetter))
        return nodes
    }

    /// `index`から始まる英語のノード
    func englishNodes(letters: [Character], at index: Int, isFinal: Bool) -> [Node] {
        let count = letters.count
        let firstIsUppercase = RomajiSyllableCost.isUppercaseLetter(letters[index])
        var nodes: [Node] = []
        var word = ""
        for end in index + 1 ... min(count, index + Self.maxEnglishWordLength) {
            word.append(letters[end - 1])
            let length = end - index
            if length == 1 {
                if word == "I" {
                    nodes.append(.init(end: end, cost: Cost.singleLetterI))
                } else if firstIsUppercase {
                    nodes.append(.init(end: end, cost: Cost.singleUppercase))
                }
                continue
            }
            var cost: Double = .infinity
            let isWord = self.englishWordChecker.isEnglishWord(word)
            if isWord {
                cost = Cost.englishWord(length: length)
            }
            if firstIsUppercase {
                cost = min(cost, Cost.capitalizedName(length: length))
            }
            if length >= Self.minProperNounLength, self.englishWordChecker.properNounSpelling(word) != nil {
                cost = min(cost, Cost.properNoun)
            }
            if end == count, !isWord, length >= 3, self.englishWordChecker.hasEnglishWord(withPrefix: word) {
                cost = min(cost, isFinal ? Cost.englishPrefixAtFinal : Cost.englishPrefix)
            }
            if cost.isFinite {
                nodes.append(.init(end: end, cost: cost))
            }
        }
        return nodes
    }

    /// ローマ字として読めても英語にする固有名詞（5文字以上）を含むか
    func containsProperNoun(_ letters: [Character]) -> Bool {
        let count = letters.count
        guard count >= Self.minProperNounLength else {
            return false
        }
        for start in 0 ... count - Self.minProperNounLength {
            var word = String(letters[start ..< start + Self.minProperNounLength - 1])
            for end in start + Self.minProperNounLength ... min(count, start + Self.maxEnglishWordLength) {
                word.append(letters[end - 1])
                if self.englishWordChecker.properNounSpelling(word) != nil {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - 探索

    /// 日本語の音節だけで読んだときの最小コスト。読めなければ`nil`
    static func japaneseOnlyCost(tokens: [[Node]], count: Int) -> Double? {
        var best = [Double](repeating: .infinity, count: count + 1)
        best[0] = 0
        for index in 0 ..< count where best[index].isFinite {
            for node in tokens[index] {
                best[node.end] = min(best[node.end], best[index] + node.cost)
            }
        }
        return best[count].isFinite ? best[count] : nil
    }

    private enum State: Int, CaseIterable {
        case start = 0
        case japanese = 1
        case english = 2
    }

    private struct Cell {
        var cost: Double = .infinity
        var previousIndex: Int = -1
        var previousState: State = .start
    }

    static func bestPath(
        letters: [Character],
        japaneseTokens: [[Node]],
        englishNodes: [[Node]],
        precededByEnglish: Bool
    ) -> [MixedLanguageSegment] {
        let count = letters.count
        var cells = [[Cell]](repeating: [Cell](repeating: Cell(), count: State.allCases.count), count: count + 1)
        cells[0][State.start.rawValue].cost = 0

        func relax(_ end: Int, _ state: State, cost: Double, from index: Int, _ previousState: State) {
            if cost < cells[end][state.rawValue].cost {
                cells[end][state.rawValue] = Cell(cost: cost, previousIndex: index, previousState: previousState)
            }
        }

        for index in 0 ..< count {
            for state in State.allCases {
                let base = cells[index][state.rawValue].cost
                guard base.isFinite else {
                    continue
                }
                // 日本語のノード
                if !japaneseTokens[index].isEmpty {
                    let transition: Double = switch state {
                    case .start: precededByEnglish ? Cost.japaneseAfterEnglishSentence : 0
                    case .japanese: 0
                    case .english: Self.englishToJapaneseCost(letters: letters, at: index)
                    }
                    for node in japaneseTokens[index] {
                        relax(node.end, .japanese, cost: base + transition + node.cost, from: index, state)
                    }
                }
                // 英語のノード
                let transition: Double = switch state {
                case .start: 0
                case .japanese: Cost.japaneseToEnglish
                case .english: Cost.englishToEnglish
                }
                for node in englishNodes[index] {
                    relax(node.end, .english, cost: base + transition + node.cost + Cost.englishTieBreak, from: index, state)
                }
            }
        }

        // 末尾から辿る
        let japaneseEnd = cells[count][State.japanese.rawValue].cost
        let englishEnd = cells[count][State.english.rawValue].cost
        guard japaneseEnd.isFinite || englishEnd.isFinite else {
            return [.init(range: 0 ..< count, language: .japanese)]
        }
        var state: State = japaneseEnd <= englishEnd ? .japanese : .english
        var index = count
        var reversed: [MixedLanguageSegment] = []
        while index > 0 {
            let cell = cells[index][state.rawValue]
            let language: MixedLanguageSegment.Language = state == .english ? .english : .japanese
            if let last = reversed.last, last.language == language {
                reversed[reversed.count - 1].range = cell.previousIndex ..< last.range.upperBound
            } else {
                reversed.append(.init(range: cell.previousIndex ..< index, language: language))
            }
            index = cell.previousIndex
            state = cell.previousState
        }
        return reversed.reversed()
    }

    /// 英語から日本語に切り替えるコスト
    static func englishToJapaneseCost(letters: [Character], at index: Int) -> Double {
        var cost = Cost.englishToJapanese
        let rest = letters[index...]
        if Self.attachedWords.contains(where: { rest.starts(with: $0) }) {
            cost = Cost.englishToAttachedWord
        }
        if index > 0, let first = rest.first, RomajiSyllableCost.isVowel(first) {
            let previous = letters[index - 1]
            if RomajiSyllableCost.isLowercaseLetter(previous), !RomajiSyllableCost.isVowel(previous) {
                cost += Cost.vowelAfterEnglish
            }
        }
        return cost
    }
}
