import Foundation
import SwiftSoup

public enum TranslationDirection: String, CaseIterable, Identifiable {
    case uzEn, enUz, uzRu, ruUz, uzCyrl, cyrlUz
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .uzEn: return "Uzbek → English"
        case .enUz: return "English → Uzbek"
        case .uzRu: return "Uzbek → Russian"
        case .ruUz: return "Russian → Uzbek"
        case .uzCyrl: return "Lotin → Кирилл"
        case .cyrlUz: return "Кирилл → Lotin"
        }
    }
    public var languages: (String, String) {
        switch self {
        case .uzEn: return ("uz-Latn", "en")
        case .enUz: return ("en", "uz-Latn")
        case .uzRu: return ("uz-Latn", "ru")
        case .ruUz: return ("ru", "uz-Latn")
        case .uzCyrl: return ("uz-Latn", "uz-Cyrl")
        case .cyrlUz: return ("uz-Cyrl", "uz-Latn")
        }
    }
}

public enum AssistantError: LocalizedError {
    case configuration, empty, tooLong, http(Int), invalidResponse, notFound, queryTooLong
    public var errorDescription: String? {
        switch self {
        case .configuration: return "Set a valid HTTPS translation URL and API key in Settings."
        case .empty: return "Select a word or open an editable draft first, or enter text here."
        case .tooLong: return "Translate up to 20,000 characters at a time. Your draft was not truncated."
        case .http(let code):
            switch code {
            case 401, 403: return "The service rejected this API key. Check Translation Settings."
            case 429: return "The service is busy. Please try again shortly."
            default: return "The source returned HTTP \(code). Please try again."
            }
        case .invalidResponse: return "The source returned an incomplete or unsupported response."
        case .notFound: return "No definition found. Try the dictionary form of the word or open the source."
        case .queryTooLong: return "Look up a word or short phrase (up to 120 characters)."
        }
    }
}

public struct TranslationConfiguration {
    public let endpoint: URL
    public let token: String
    public init(baseURL: String, token: String, allowInsecureHTTP: Bool = false) throws {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              (url.scheme == "https" || (allowInsecureHTTP && url.scheme == "http")), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AssistantError.configuration }
        let base = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.hasSuffix("api/translate/text") { endpoint = url }
        else { endpoint = url.appendingPathComponent("api/translate/text") }
        self.token = token
    }
    public func request(text: String, direction: TranslationDirection) throws -> URLRequest {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AssistantError.empty }
        guard text.unicodeScalars.count <= 20_000 else { throw AssistantError.tooLong }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-API-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["sourceLanguage": direction.languages.0, "targetLanguage": direction.languages.1, "text": text])
        return request
    }
}

/// Only a completed stream may be copied/applied. Partial deltas are a preview.
public struct TranslationStream {
    public private(set) var text = ""
    public private(set) var done = false
    public init() {}
    public mutating func consume(_ line: String) throws {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !done, let data = line.data(using: .utf8),
              let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AssistantError.invalidResponse }
        if event["error"] != nil { throw AssistantError.invalidResponse }
        if let delta = event["delta"] as? String { text += delta }
        if event["done"] as? Bool == true { done = true }
        guard text.utf8.count <= 2_000_000 else { throw AssistantError.invalidResponse }
    }
    public func completedText() throws -> String {
        guard done, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AssistantError.invalidResponse }
        return text
    }
}

public enum TranslationService {
    public static func translate(_ text: String, direction: TranslationDirection, configuration: TranslationConfiguration,
                                 session: URLSession, progress: @escaping (String) async -> Void) async throws -> String {
        let (bytes, response) = try await session.bytes(for: configuration.request(text: text, direction: direction))
        guard let response = response as? HTTPURLResponse else { throw AssistantError.invalidResponse }
        guard response.statusCode == 200 else { throw AssistantError.http(response.statusCode) }
        var stream = TranslationStream(), last = Date.distantPast, count = 0
        for try await line in bytes.lines {
            try Task.checkCancellation()
            count += line.utf8.count
            guard count <= 2_000_000 else { throw AssistantError.invalidResponse }
            try stream.consume(line)
            if Date().timeIntervalSince(last) > 0.08 { await progress(stream.text); last = Date() }
        }
        return try stream.completedText()
    }
}

public struct DictionaryMeaning: Equatable, Identifiable {
    public let definition: String
    public let examples: [String]
    public var id: String { definition }
    public init(definition: String, examples: [String]) { self.definition = definition; self.examples = examples }
}
public struct DictionaryEntry: Equatable {
    public let word: String
    public let meanings: [DictionaryMeaning]
    public let source: URL
    public var preview: [DictionaryMeaning] {
        Array(meanings.prefix(2)).map { DictionaryMeaning(definition: $0.definition, examples: Array($0.examples.prefix(1))) }
    }
    public init(word: String, meanings: [DictionaryMeaning], source: URL) { self.word = word; self.meanings = meanings; self.source = source }
}
public enum DictionaryService {
    /// A selection is an explicit phrase. Otherwise inspect only the word at
    /// the caret, so dictionary preparation never sends an entire paragraph.
    public static func query(in text: String, selection: NSRange?) -> String {
        let ns = text as NSString
        if let selection, selection.location >= 0, selection.length > 0,
           selection.location <= ns.length, selection.length <= ns.length - selection.location {
            return ns.substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if selection == nil, text.count <= 120, !text.contains("\n"), text.split(whereSeparator: { $0.isWhitespace }).count <= 5 {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let caret = min(ns.length, max(0, selection?.location ?? ns.length))
        let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{M}]+(?:['‘’ʻʼ-][\p{L}\p{M}]+)*"#)
        let words = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let word = words.first { $0.range.location <= caret && NSMaxRange($0.range) >= caret }
            ?? words.last { NSMaxRange($0.range) <= caret }
        return word.map { ns.substring(with: $0.range) } ?? ""
    }
    public static func normalizedQuery(_ query: String) throws -> String {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { throw AssistantError.empty }
        guard value.count <= 120, value.split(whereSeparator: { $0.isWhitespace }).count <= 10 else { throw AssistantError.queryTooLong }
        return value.replacingOccurrences(of: "ö", with: "o‘").replacingOccurrences(of: "ğ", with: "g‘")
            .replacingOccurrences(of: "ş", with: "sh").replacingOccurrences(of: "ç", with: "ch")
    }
    public static func sourceURL(_ query: String) throws -> URL {
        let value = try normalizedQuery(query)
        return URL(string: "https://izoh.uz/word/")!.appendingPathComponent(value)
    }
    public static func parse(_ html: String, source: URL) throws -> DictionaryEntry {
        let doc = try SwiftSoup.parse(html)
        guard let title = try doc.select("h1[itemprop=name]").first()?.text(), !title.isEmpty else { throw AssistantError.notFound }
        var meanings: [DictionaryMeaning] = []
        for block in try doc.select("div[id^=def-]") {
            // Direct children exclude examples, synonyms, ads and community contributions.
            for node in block.children() where node.tagName() == "p" {
                guard node.hasClass("font-bold") else { continue }
                let definition = try node.text().replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
                var examples: [String] = []
                if let next = try node.nextElementSibling(), next.tagName() == "ol" {
                    examples = try next.select("li").array().map { try $0.text() }
                }
                if !definition.isEmpty { meanings.append(DictionaryMeaning(definition: definition, examples: examples)) }
            }
        }
        guard !meanings.isEmpty else { throw AssistantError.notFound }
        return DictionaryEntry(word: title, meanings: meanings, source: source)
    }
    public static func lookup(_ query: String, session: URLSession) async throws -> DictionaryEntry {
        let url = try sourceURL(query)
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw AssistantError.invalidResponse }
        guard response.statusCode == 200 else { throw response.statusCode == 404 ? AssistantError.notFound : AssistantError.http(response.statusCode) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else { throw AssistantError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard let html = String(data: data, encoding: .utf8) else { throw AssistantError.invalidResponse }
        return try parse(html, source: url)
    }
}

public struct DocumentStatistics {
    public let words: Int
    public let characters: Int
    public let paragraphs: Int
    public var readingMinutes: Int { max(1, Int(ceil(Double(words) / 200))) }
    public init(_ text: String) {
        words = text.split(whereSeparator: { $0.isWhitespace }).filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }.count
        characters = text.count
        paragraphs = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}
public enum DocumentCleanup {
    /// Preserve line/paragraph breaks and indentation; clean repeated intra-line
    /// spaces and trailing whitespace only. This is never applied automatically.
    public static func clean(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            let body = String(line.dropFirst(indent.count)).replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
                .replacingOccurrences(of: " +$", with: "", options: .regularExpression)
            return body.isEmpty ? "" : indent + body
        }.joined(separator: "\n")
    }
}
