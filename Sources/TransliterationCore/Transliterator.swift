import Foundation

public struct WordSuggestion: Equatable {
    public let original: String
    public let replacement: String
    /// UTF-16 offsets, matching macOS Accessibility ranges.
    public let range: NSRange
    public let atBoundary: Bool
    public init(original: String, replacement: String, range: NSRange, atBoundary: Bool) {
        self.original = original; self.replacement = replacement; self.range = range; self.atBoundary = atBoundary
    }
}

/// Implements the alphabet table on pages 2–3 of the user-provided PDF.
/// This is a character transliterator, not a spelling or language detector.
public enum Transliterator {
    public static let alphabet = ["A", "B", "D", "E", "F", "G", "Ğ", "H", "I", "J", "K", "L", "M", "N", "O", "Ö", "P", "Q", "R", "S", "Ş", "Ç", "T", "U", "V", "X", "Y", "Z"]
    private static let marks = Set<Character>(["'", "‘", "’", "ʻ", "ʼ", "`", "ʹ", "´", "＇"])
    private static let protected = try! NSRegularExpression(pattern: #"(?i)(?:https?://|www\.)\S+|[\p{L}\d._%+\-]+@[\p{L}\d.\-]+\.[\p{L}]{2,}|\b[\p{L}\d\-]+(?:\.[\p{L}\d\-]+)+\b"#)

    public struct Run: Equatable {
        public let text: String
        public let changed: Bool
    }
    public static func convert(_ text: String) -> String { runs(in: text).map(\.text).joined() }

    /// Linear conversion with precise highlight spans; protected addresses keep
    /// their original appearance, including any existing Uzbek letters.
    public static func runs(in text: String) -> [Run] {
        let source = text.precomposedStringWithCanonicalMapping
        let ns = source as NSString
        var result: [Run] = [], cursor = 0
        var pending = "", pendingChanged = false
        func append(_ text: String, changed: Bool) {
            guard !text.isEmpty else { return }
            if changed != pendingChanged, !pending.isEmpty {
                result.append(Run(text: pending, changed: pendingChanged)); pending = ""
            }
            pendingChanged = changed; pending.append(contentsOf: text)
        }
        func letters(_ text: String) {
            let chars = Array(text)
            var i = 0
            while i < chars.count {
                let c = chars[i], lower = String(c).lowercased()
                if i + 1 < chars.count {
                    let next = chars[i + 1], pair = lower + String(next).lowercased()
                    let mapped: String?
                    if (lower == "o" || lower == "g") && marks.contains(next) { mapped = lower == "o" ? "ö" : "ğ" }
                    else { mapped = ["sh": "ş", "ch": "ç"][pair] }
                    if let mapped {
                        append(c.isUppercase ? mapped.uppercased() : mapped, changed: true)
                        i += 2; continue
                    }
                }
                if marks.contains(c), i > 0, i + 1 < chars.count,
                   chars[i - 1].isLetter, chars[i + 1].isLetter {
                    append("’", changed: c != "’")
                } else { append(String(c), changed: false) }
                i += 1
            }
        }
        for match in protected.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            letters(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            append(ns.substring(with: match.range), changed: false)
            cursor = NSMaxRange(match.range)
        }
        letters(ns.substring(from: cursor))
        if !pending.isEmpty { result.append(Run(text: pending, changed: pendingChanged)) }
        return result
    }

    public static func suggestion(in context: String, caret: Int) -> WordSuggestion? {
        let text = context as NSString
        guard caret > 0, caret <= text.length,
              let prefixRange = Range(NSRange(location: 0, length: caret), in: context) else { return nil }
        let prefix = String(context[prefixRange])
        let tokenPattern = #"[\p{L}\p{M}'‘’ʻʼ`ʹ´＇]+[\s.,!?;:]{0,3}$"#
        guard let r = prefix.range(of: tokenPattern, options: .regularExpression) else { return nil }
        let chunk = String(prefix[r])
        let token = String(chunk.prefix { $0.isLetter || $0.isMark || marks.contains($0) })
        guard !token.isEmpty, token.count < 100 else { return nil }
        let start = NSRange(r, in: prefix).location
        // Do not replace part of an address, URL, identifier, or a word edited in its middle.
        if start > 0 {
            let before = text.substring(with: NSRange(location: start - 1, length: 1))
            if "@/._-\\".contains(before) { return nil }
        }
        if caret < text.length,
           let nextRange = Range(NSRange(location: caret, length: 1), in: context),
           let next = context[nextRange].first,
           next.isLetter || next.isNumber || "@/._".contains(next) { return nil }
        let replacement = convert(token)
        guard replacement != token else { return nil }
        return WordSuggestion(original: token, replacement: replacement,
                              range: NSRange(location: start, length: (token as NSString).length),
                              atBoundary: chunk != token)
    }

    /// Preview the complete paragraph before the cursor, including earlier
    /// sentences and unchanged final words. A bounded AX window must never cause
    /// a partial paragraph to be replaced without the user seeing its full scope.
    public static func paragraphSuggestion(in context: String, caret: Int, startsAtDocumentStart: Bool = true) -> WordSuggestion? {
        let ns = context as NSString
        guard caret > 0, caret <= ns.length,
              let prefixRange = Range(NSRange(location: 0, length: caret), in: context) else { return nil }
        let prefix = String(context[prefixRange])
        if let previous = prefix.last, previous.isLetter || previous.isNumber,
           caret < ns.length, let suffixRange = Range(NSRange(location: caret, length: ns.length - caret), in: context),
           let next = context[suffixRange].first, next.isLetter || next.isNumber { return nil }
        let startIndex = prefix.lastIndex(where: { $0.isNewline }).map { prefix.index(after: $0) } ?? prefix.startIndex
        guard startsAtDocumentStart || startIndex != prefix.startIndex else { return nil }
        let original = String(prefix[startIndex...])
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let converted = convert(original)
        guard converted != original else { return nil }
        return WordSuggestion(original: original, replacement: converted,
                              range: NSRange(startIndex..<prefix.endIndex, in: prefix),
                              atBoundary: original.last.map { !$0.isLetter && !$0.isNumber } ?? false)
    }

    /// Convert the complete editable field, including text after the cursor,
    /// blank lines, and all paragraphs. Never silently truncate the scope.
    public static func fieldSuggestion(in text: String) -> WordSuggestion? {
        let replacement = convert(text)
        guard replacement != text else { return nil }
        return WordSuggestion(original: text, replacement: replacement,
                              range: NSRange(location: 0, length: (text as NSString).length), atBoundary: true)
    }

    public static func convertedCaret(in text: String, utf16Location: Int) -> Int? {
        guard utf16Location >= 0, utf16Location <= text.utf16.count else { return nil }
        let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: utf16Location)
        guard let index = String.Index(utf16Index, within: text) else { return nil }
        return convert(String(text[..<index])).utf16.count
    }
}

private extension Character {
    var isMark: Bool { unicodeScalars.allSatisfy { CharacterSet.nonBaseCharacters.contains($0) } }
}
