import XCTest
@testable import AssistantCore

final class PublicTranslationTests: XCTestCase {
    func testPublicRequestsHaveNoCredentialsAndUseSupportedLanguagePairs() throws {
        for direction in [TranslationDirection.uzEn, .enUz, .uzRu, .ruUz] {
            let request = try PublicTranslationService.request(text: "O'zbekcha & matn?", direction: direction)
            XCTAssertEqual(request.url?.host, "api.mymemory.translated.net")
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-API-Token"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(Set(query.map(\.name)), ["q", "langpair", "mt"])
            XCTAssertEqual(query.first { $0.name == "q" }?.value, "O'zbekcha & matn?")
        }
    }
    func testSegmentsRespectUTF8LimitPreserveEveryCharacterAndParagraph() throws {
        let input = "  " + String(repeating: "O‘zbekcha 👩🏽‍💻 matn. ", count: 45) + "\r\n\r\n\tIkkinchi qator.  \n"
        let segments = try PublicTranslationService.segments(input)
        XCTAssertEqual(segments.map(\.text).joined(), input)
        let translated = segments.filter(\.translate)
        XCTAssertGreaterThan(translated.count, 2)
        XCTAssertTrue(translated.allSatisfy { $0.text.utf8.count <= 500 && !$0.text.contains("\r") && !$0.text.contains("\n") })
        XCTAssertTrue(segments.contains { !$0.translate && $0.text.contains("\r\n\r\n") })
    }
    func testRejectsOversizeDraftWithoutTruncationAndDecodesLiteralEntities() throws {
        XCTAssertThrowsError(try PublicTranslationService.segments(String(repeating: "a", count: 5_001)))
        XCTAssertThrowsError(try PublicTranslationService.request(text: "first\nsecond", direction: .uzEn))
        XCTAssertThrowsError(try PublicTranslationService.segments("  \n"))
        let data = Data(#"{"responseStatus":200,"responseData":{"translatedText":" Hello &amp; &lt;world&gt;! "}}"#.utf8)
        XCTAssertEqual(try PublicTranslationService.parse(data), "Hello & <world>!")
        let quota = Data(#"{"responseStatus":403,"quotaFinished":true,"responseDetails":"private details"}"#.utf8)
        XCTAssertThrowsError(try PublicTranslationService.parse(quota)) { error in
            XCTAssertTrue(error.localizedDescription.contains("quota")); XCTAssertFalse(error.localizedDescription.contains("private details"))
        }
    }
    func testLocalScriptMappingPreservesCaseParagraphsAndAddresses() {
        let samples = [("O'zbekiston Respublikasi", "Ўзбекистон Республикаси"), ("ishchi", "ишчи"), ("akkreditatsiya", "аккредитация"), ("eshik", "эшик"), ("yer", "ер"), ("ketsa", "кетса"), ("Yevropa", "Европа"), ("poetika", "поэтика"), ("Shahar", "Шаҳар"), ("SHAHAR", "ШАҲАР")]
        for (latin, cyrillic) in samples { XCTAssertEqual(UzbekScript.convert(latin, toCyrillic: true), cyrillic) }
        XCTAssertEqual(UzbekScript.convert("ЁЗ\n\nЎзбекистон — маъно", toCyrillic: false), "YOZ\n\nO‘zbekiston — ma’no")
        XCTAssertEqual(UzbekScript.convert("Özbekça şahar va ğoya", toCyrillic: true), "Ўзбекча шаҳар ва ғоя")
        let address = "https://shahar.uz admin@example.com hisobot.docx"
        XCTAssertEqual(UzbekScript.convert(address, toCyrillic: true), address)
    }
}

private final class PublicFixtureProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    static var quotaOnSecond = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        let text = query.first { $0.name == "q" }!.value!
        let body: [String: Any] = Self.quotaOnSecond && Self.requests.count > 1
            ? ["responseStatus":403, "quotaFinished":true]
            : ["responseStatus":200, "responseData":["translatedText": "Translated " + text]]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class PublicTranslationTransportTests: XCTestCase {
    private func session() -> URLSession {
        PublicFixtureProtocol.requests = []; PublicFixtureProtocol.quotaOnSecond = false
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PublicFixtureProtocol.self]
        return URLSession(configuration: config)
    }
    func testWholeDraftKeepsParagraphBreaksAndUsesOnlyPublicRequests() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let output = try await PublicTranslationService.translate("  First paragraph.\n\nSecond paragraph.\n", direction: .enUz, session: session) { _ in }
        XCTAssertEqual(output, "  Translated First paragraph.\n\nTranslated Second paragraph.\n")
        XCTAssertEqual(PublicFixtureProtocol.requests.count, 2)
        XCTAssertTrue(PublicFixtureProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-API-Token") == nil })
    }
    func testScriptDirectionsStayOffline() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let cyrillic = try await PublicTranslationService.translate("Shahar", direction: .uzCyrl, session: session) { _ in }
        let latin = try await PublicTranslationService.translate("Шаҳар", direction: .cyrlUz, session: session) { _ in }
        XCTAssertEqual(cyrillic, "Шаҳар"); XCTAssertEqual(latin, "Shahar")
        XCTAssertTrue(PublicFixtureProtocol.requests.isEmpty)
    }
    func testQuotaFailureNeverReturnsPartialSuccess() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        PublicFixtureProtocol.quotaOnSecond = true
        do {
            _ = try await PublicTranslationService.translate("First paragraph.\n\nSecond paragraph.", direction: .enUz, session: session) { _ in }
            XCTFail("Partial translations must not be treated as completed")
        } catch { XCTAssertTrue(error.localizedDescription.contains("quota")) }
    }
}
