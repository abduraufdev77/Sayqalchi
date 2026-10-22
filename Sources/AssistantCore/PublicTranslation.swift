import Foundation
import SwiftSoup

public enum TranslationProvider: String, CaseIterable, Identifiable {
    case myMemory, custom
    public var id: String { rawValue }
    public var title: String { self == .myMemory ? "MyMemory · free" : "Custom service" }
}

public enum PublicTranslationError: LocalizedError {
    case tooLong, quota, unavailable
    public var errorDescription: String? {
        switch self {
        case .tooLong: return "MyMemory allows 5,000 characters per day anonymously. Use a shorter draft or your custom service; nothing was truncated."
        case .quota: return "MyMemory’s free daily quota is used up. Try tomorrow or select your custom service in Settings."
        case .unavailable: return "MyMemory could not translate this text. Try again or select your custom service in Settings."
        }
    }
}

/// Documented anonymous API: no shared key, login, contact email or private
/// service headers. Each request contains at most one paragraph and 500 bytes.
public enum PublicTranslationService {
    public struct Segment: Equatable {
        public let text: String
        public let translate: Bool
    }
    public static func segments(_ text: String) throws -> [Segment] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AssistantError.empty }
        guard text.unicodeScalars.count <= 5_000 else { throw PublicTranslationError.tooLong }
        let ns = text as NSString
        let regex = try NSRegularExpression(pattern: #"[^\r\n]+|[\r\n]+"#)
        var result: [Segment] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var remaining = ns.substring(with: match.range)
            while !remaining.isEmpty {
                let whitespace = String(remaining.prefix(while: { $0.isWhitespace }))
                if !whitespace.isEmpty {
                    result.append(Segment(text: whitespace, translate: false))
                    remaining.removeFirst(whitespace.count); continue
                }
                let trailing = String(remaining.reversed().prefix(while: { $0.isWhitespace }).reversed())
                let body = String(remaining.dropLast(trailing.count))
                var end = body.startIndex, bytes = 0
                while end < body.endIndex {
                    let next = body.index(after: end), count = body[end..<next].utf8.count
                    if bytes + count > 500 { break }
                    bytes += count; end = next
                }
                guard end > body.startIndex else { throw PublicTranslationError.tooLong }
                if end < body.endIndex, let space = body[..<end].lastIndex(where: { $0.isWhitespace }) { end = space }
                let chunk = String(body[..<end])
                result.append(Segment(text: chunk, translate: true))
                remaining.removeFirst(chunk.count)
            }
        }
        return result
    }
    public static func request(text: String, direction: TranslationDirection) throws -> URLRequest {
        guard !text.isEmpty, text.utf8.count <= 500, !text.contains("\n"), !text.contains("\r") else { throw PublicTranslationError.tooLong }
        let pair: String
        switch direction {
        case .uzEn: pair = "uz|en"
        case .enUz: pair = "en|uz"
        case .uzRu: pair = "uz|ru"
        case .ruUz: pair = "ru|uz"
        case .uzCyrl, .cyrlUz: throw PublicTranslationError.unavailable
        }
        var url = URLComponents(string: "https://api.mymemory.translated.net/get")!
        url.queryItems = [URLQueryItem(name: "q", value: text), URLQueryItem(name: "langpair", value: pair), URLQueryItem(name: "mt", value: "1")]
        var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    public static func parse(_ data: Data) throws -> String {
        guard data.count <= 2_000_000, let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AssistantError.invalidResponse }
        let status = (body["responseStatus"] as? NSNumber)?.intValue ?? Int(body["responseStatus"] as? String ?? "")
        if body["quotaFinished"] as? Bool == true || status == 429 { throw PublicTranslationError.quota }
        guard status == 200, let result = body["responseData"] as? [String: Any],
              let raw = result["translatedText"] as? String, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PublicTranslationError.unavailable }
        // Decode entities as text, without treating translated markup as HTML.
        let decoded = try Entities.unescape(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decoded.isEmpty else { throw AssistantError.invalidResponse }
        return decoded
    }
    public static func translate(_ text: String, direction: TranslationDirection, session: URLSession,
                                 progress: @escaping (String) async -> Void) async throws -> String {
        if direction == .uzCyrl || direction == .cyrlUz {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AssistantError.empty }
            guard text.unicodeScalars.count <= 20_000 else { throw AssistantError.tooLong }
            return UzbekScript.convert(text, toCyrillic: direction == .uzCyrl)
        }
        var output = ""
        for segment in try segments(text) {
            try Task.checkCancellation()
            if !segment.translate { output += segment.text; continue }
            let (bytes, response) = try await session.bytes(for: request(text: segment.text, direction: direction))
            guard let response = response as? HTTPURLResponse else { throw AssistantError.invalidResponse }
            if response.statusCode == 429 { throw PublicTranslationError.quota }
            guard response.statusCode == 200 else { throw PublicTranslationError.unavailable }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 2_000_000 else { throw AssistantError.invalidResponse }
                data.append(byte)
            }
            output += try parse(data)
            await progress(output)
        }
        try Task.checkCancellation()
        return output
    }
}
