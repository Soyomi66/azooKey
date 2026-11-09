//
//  EnglishWordChecking.swift
//  AzooKeyCore
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 英字の並びが英単語かどうかを調べる。
@MainActor
public protocol EnglishWordChecking: AnyObject {
    /// `word`が英単語として正しい綴りか
    func isEnglishWord(_ word: String) -> Bool
    /// `prefix`で始まる英単語があるか
    func hasEnglishWord(withPrefix prefix: String) -> Bool
    /// `word`が固有名詞なら、その正しい表記（`iphone` → `iPhone`）。固有名詞でなければ`nil`
    func properNounSpelling(_ word: String) -> String?
}

/// 決まった単語の集合で判定する。テストやユーザー辞書の語に使う。
@MainActor
public final class EnglishWordSetChecker: EnglishWordChecking {
    private let words: Set<String>
    private let prefixes: Set<String>
    private let properNouns: [String: String]

    /// - Parameters:
    ///   - words: 英単語の一覧。大文字・小文字は区別しない。
    ///   - properNouns: 固有名詞の一覧。正しい表記で書く。英単語としても扱う。
    public init(words: some Sequence<String>, properNouns: some Sequence<String> = [String]()) {
        var spellings: [String: String] = [:]
        for word in properNouns {
            spellings[word.lowercased()] = spellings[word.lowercased()] ?? word
        }
        self.properNouns = spellings
        let words = Set(words.map { $0.lowercased() }).union(spellings.keys)
        self.words = words
        var prefixes: Set<String> = []
        for word in words {
            for length in 1 ... word.count {
                prefixes.insert(String(word.prefix(length)))
            }
        }
        self.prefixes = prefixes
    }

    public func isEnglishWord(_ word: String) -> Bool {
        self.words.contains(word.lowercased())
    }

    public func hasEnglishWord(withPrefix prefix: String) -> Bool {
        self.prefixes.contains(prefix.lowercased())
    }

    public func properNounSpelling(_ word: String) -> String? {
        self.properNouns[word.lowercased()]
    }
}

/// 同梱の辞書（`BuiltInEnglishWords`）を小文字で引き、無ければOSのスペルチェッカー（`UITextChecker`）で調べる。
/// スペルチェッカーは`iPhone`のような固有名詞を正しい大文字小文字でしか認めないので、小文字で打つ語を同梱の辞書で補う。
/// 同じ綴りを何度も調べないよう、スペルチェッカーの結果をキャッシュする。
@MainActor
public final class SystemEnglishWordChecker: EnglishWordChecking {
    public init(language: String = "en_US") {
        self.language = language
    }

    private let language: String
    private var wordCache: [String: Bool] = [:]
    private var prefixCache: [String: Bool] = [:]
    /// キャッシュの上限。超えたら捨てる
    private static let cacheLimit = 4096

    #if canImport(UIKit)
    private lazy var checker = UITextChecker()
    #endif

    public func isEnglishWord(_ word: String) -> Bool {
        if BuiltInEnglishWords.lowercasedWords.contains(word.lowercased()) {
            return true
        }
        if let cached = self.wordCache[word] {
            return cached
        }
        let result = self.checkSpelling(word)
        if self.wordCache.count >= Self.cacheLimit {
            self.wordCache.removeAll(keepingCapacity: true)
        }
        self.wordCache[word] = result
        return result
    }

    public func hasEnglishWord(withPrefix prefix: String) -> Bool {
        if BuiltInEnglishWords.prefixes.contains(prefix.lowercased()) {
            return true
        }
        if let cached = self.prefixCache[prefix] {
            return cached
        }
        let result: Bool
        if prefix.count > 1, self.prefixCache[String(prefix.dropLast())] == false {
            // 1文字短い頭で始まる語がなければ、この頭で始まる語もない。
            // 1文字打つたびに末尾の頭を調べるので、補完の問い合わせをここで減らす
            result = false
        } else {
            result = !self.completions(for: prefix).isEmpty
        }
        if self.prefixCache.count >= Self.cacheLimit {
            self.prefixCache.removeAll(keepingCapacity: true)
        }
        self.prefixCache[prefix] = result
        return result
    }

    public func properNounSpelling(_ word: String) -> String? {
        BuiltInEnglishWords.properNounSpellings[word.lowercased()]
    }

    private func checkSpelling(_ word: String) -> Bool {
        guard !word.isEmpty else {
            return false
        }
        let range = NSRange(location: 0, length: word.utf16.count)
        #if canImport(UIKit)
        let misspelled = self.checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: self.language)
        return misspelled.location == NSNotFound
        #elseif canImport(AppKit)
        let misspelled = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: self.language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return misspelled.location == NSNotFound
        #else
        return false
        #endif
    }

    private func completions(for prefix: String) -> [String] {
        guard !prefix.isEmpty else {
            return []
        }
        let range = NSRange(location: 0, length: prefix.utf16.count)
        #if canImport(UIKit)
        return self.checker.completions(forPartialWordRange: range, in: prefix, language: self.language) ?? []
        #elseif canImport(AppKit)
        return NSSpellChecker.shared.completions(forPartialWordRange: range, in: prefix, language: self.language, inSpellDocumentWithTag: 0) ?? []
        #else
        return []
        #endif
    }
}
