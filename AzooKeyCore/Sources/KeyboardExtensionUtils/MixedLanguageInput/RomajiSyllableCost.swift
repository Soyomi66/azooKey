//
//  RomajiSyllableCost.swift
//  AzooKeyCore
//
//  日英混在入力で、英字の並びを「日本語のローマ字としてどれだけ自然に読めるか」を測るための音節表。
//  キーの一覧はazooKeyの既定のローマ字かな変換表に合わせている。
//

/// ローマ字の音節ごとの「日本語らしくなさ」のコスト。
/// 0 はふつうの日本語でよく打つ音節、値が大きいほど日本語を打つときには使わない綴りであることを表す。
enum RomajiSyllableCost {
    /// ふつうの日本語で打つ音節（ヘボン式・訓令式の両方を含む）
    static let common: Double = 0
    /// カタカナ語でよく打つ音節（ふぁ、てぃ、うぃ など）
    static let loanword: Double = 0.3
    /// c で打つ か行・さ行（ca、ce など）。日本語を打つときはふつう k・s を使う
    static let cRow: Double = 0.5
    /// 日本語ではほとんど打たない音節（ぐぉ、ぁ、ゎ など）
    static let rare: Double = 2.0
    /// 記号になる綴り（zh → ← など）
    static let symbol: Double = 3.0

    /// 子音を重ねて打つ「っ」のコスト
    static func sokuon(_ consonant: Character) -> Double {
        switch consonant {
        case "k", "s", "t", "p", "c":
            // 学校、雑誌、切手、一杯、抹茶(macca)
            return common
        case "g", "z", "d", "b":
            // バッグ、ベッド など、カタカナ語で使う
            return 0.5
        default:
            return rare
        }
    }

    /// 音節の最大の長さ（xtsu など）
    static let maxSyllableLength = 4

    /// ローマ字の綴り（小文字）からコストを引く表
    static let table: [String: Double] = {
        var table: [String: Double] = [:]
        func set(_ cost: Double, _ keys: [String]) {
            for key in keys {
                table[key] = cost
            }
        }
        set(common, [
            "a", "i", "u", "e", "o",
            "ka", "ki", "ku", "ke", "ko", "ga", "gi", "gu", "ge", "go",
            "sa", "si", "shi", "su", "se", "so", "za", "zi", "ji", "zu", "ze", "zo",
            "ta", "ti", "chi", "tu", "tsu", "te", "to", "da", "di", "du", "de", "do",
            "na", "ni", "nu", "ne", "no",
            "ha", "hi", "hu", "fu", "he", "ho", "ba", "bi", "bu", "be", "bo", "pa", "pi", "pu", "pe", "po",
            "ma", "mi", "mu", "me", "mo", "ya", "yu", "yo", "ra", "ri", "ru", "re", "ro", "wa", "wo", "nn",
            "kya", "kyu", "kyo", "gya", "gyu", "gyo",
            "sha", "shu", "sho", "sya", "syu", "syo",
            "ja", "ju", "jo", "zya", "zyu", "zyo", "jya", "jyu", "jyo",
            "cha", "chu", "cho", "tya", "tyu", "tyo", "cya", "cyu", "cyo",
            "nya", "nyu", "nyo", "hya", "hyu", "hyo", "bya", "byu", "byo", "pya", "pyu", "pyo",
            "mya", "myu", "myo", "rya", "ryu", "ryo",
        ])
        set(loanword, [
            "fa", "fi", "fe", "fo", "fyu",
            "she", "sye", "je", "jye", "zye", "che", "cye", "tye",
            "thi", "dhi", "dhu", "twu", "dwu",
            "wi", "we", "ye",
            "va", "vi", "vu", "ve", "vo",
        ])
        set(cRow, ["ca", "ci", "cu", "ce", "co"])
        set(rare, [
            "xa", "xi", "xu", "xe", "xo", "la", "li", "lu", "le", "lo",
            "xka", "lka", "xke", "lke",
            "xtu", "ltu", "xtsu", "ltsu",
            "xya", "lya", "xyu", "lyu", "xyo", "lyo", "xwa", "lwa", "xn",
            "wu", "wyi", "wye",
            "kye", "gye",
            "qa", "qi", "qu", "qe", "qo",
            "kwa", "kwi", "kwu", "kwe", "kwo", "qwa", "qwi", "qwu", "qwe", "qwo",
            "gwa", "gwi", "gwu", "gwe", "gwo",
            "swa", "swi", "swu", "swe", "swo",
            "tsa", "tsi", "tse", "tso",
            "tha", "thu", "the", "tho",
            "twa", "twi", "twe", "two",
            "dya", "dyi", "dyu", "dye", "dyo",
            "dha", "dhe", "dho",
            "dwa", "dwi", "dwe", "dwo",
            "jyi", "tyi", "cyi",
            "nyi", "nye", "hyi", "hye", "byi", "bye", "pyi", "pye", "myi", "mye", "ryi", "rye",
            "hwa", "hwi", "hwe", "hwo",
            "fwa", "fwi", "fwu", "fwe", "fwo", "fya", "fyo",
            "wha", "whi", "whu", "whe", "who",
        ])
        set(symbol, ["zh", "zj", "zk", "zl"])
        return table
    }()

    /// 音節の途中まで打った状態の綴り（k、ky、ts など）。入力の末尾にあるときは、続きを打てば日本語になる。
    static let pendingPrefixes: Set<String> = {
        var prefixes: Set<String> = []
        for key in table.keys where key.count >= 2 {
            for length in 1 ..< key.count {
                prefixes.insert(String(key.prefix(length)))
            }
        }
        // 子音を重ねて打つ「っ」の途中
        prefixes.formUnion("bcdfghjklmpqrstvwxyz".map { String($0) })
        return prefixes.subtracting(table.keys)
    }()

    static func isVowel(_ character: Character) -> Bool {
        switch character {
        case "a", "i", "u", "e", "o": true
        default: false
        }
    }

    static func isLowercaseLetter(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else {
            return false
        }
        return UInt8(ascii: "a") <= ascii && ascii <= UInt8(ascii: "z")
    }

    static func isUppercaseLetter(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else {
            return false
        }
        return UInt8(ascii: "A") <= ascii && ascii <= UInt8(ascii: "Z")
    }

    static func isLetter(_ character: Character) -> Bool {
        isLowercaseLetter(character) || isUppercaseLetter(character)
    }
}
