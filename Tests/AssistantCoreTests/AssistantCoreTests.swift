import XCTest
@testable import AssistantCore

final class AssistantCoreTests: XCTestCase {
    func testAllSixDirectionsAndAuthenticatedRequestContract() throws {
        let config = try TranslationConfiguration(baseURL: "https://translation.example.com/", token: "test-only-token")
        XCTAssertEqual(config.endpoint.absoluteString, "https://translation.example.com/api/translate/text")
        XCTAssertEqual(Set(TranslationDirection.allCases.map { $0.languages.0 + ":" + $0.languages.1 }).count, 6)
        for direction in TranslationDirection.allCases {
            let request = try config.request(text: "Birinchi satr.\n\nIkkinchi satr.", direction: direction)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Token"), "test-only-token")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
            XCTAssertEqual(body["text"], "Birinchi satr.\n\nIkkinchi satr.")
            XCTAssertEqual(body["sourceLanguage"], direction.languages.0)
            XCTAssertEqual(body["targetLanguage"], direction.languages.1)
        }
        let endpoint = try TranslationConfiguration(baseURL: "https://translation.example.com/api/translate/text", token: "test")
        XCTAssertEqual(endpoint.endpoint, config.endpoint)
    }
    func testRejectsInsecureOrCredentialBearingURLsAndOversizeDrafts() throws {
        for url in ["http://example.com", "https://user:password@example.com", "https://example.com?api_key=secret", "file:///tmp/service"] {
            XCTAssertThrowsError(try TranslationConfiguration(baseURL: url, token: "test"))
        }
        let optedIn = try TranslationConfiguration(baseURL: "http://localhost:5177", token: "test", allowInsecureHTTP: true)
        XCTAssertEqual(optedIn.endpoint.scheme, "http")
        let config = try TranslationConfiguration(baseURL: "https://example.com", token: "test")
        XCTAssertThrowsError(try config.request(text: String(repeating: "a", count: 20001), direction: .uzEn))
        XCTAssertThrowsError(try config.request(text: " \n", direction: .uzEn))
    }
    func testStreamRequiresDoneAndPreservesUnicodeParagraphs() throws {
        var stream = TranslationStream()
        try stream.consume(#"{"start":true}"#)
        try stream.consume(#"{"delta":"O‘zbekiston.\n\n"}"#)
        try stream.consume(#"{"delta":"Ikkinchi qator."}"#)
        XCTAssertThrowsError(try stream.completedText())
        try stream.consume(#"{"done":true}"#)
        XCTAssertEqual(try stream.completedText(), "O‘zbekiston.\n\nIkkinchi qator.")
        XCTAssertThrowsError(try stream.consume(#"{"delta":"late"}"#))
        var failure = TranslationStream()
        XCTAssertThrowsError(try failure.consume(#"{"error":"private backend trace"}"#))
        XCTAssertFalse(AssistantError.invalidResponse.localizedDescription.contains("backend"))
    }
    func testDictionaryExtractsMeaningsAndLimitsCompactExamples() throws {
        let html = """
        <h1 itemprop="name">jamoa</h1><div id="def-123">
        <p class="font-bold">1. First &amp; meaning.</p><ol><li>Example one.</li><li>Example two.</li></ol>
        <p class="font-bold">2. <i>eskirgan</i> Second meaning.</p><ol><li>One example.</li></ol>
        <p class="font-bold">3. Third meaning.</p><ol><li>Third example.</li></ol>
        <p class="font-bold">4. Fourth meaning.</p></div>
        <aside><p>Advertisement or unrelated text.</p></aside><script>alert('never execute')</script>
        """
        let entry = try DictionaryService.parse(html, source: URL(string: "https://izoh.uz/word/jamoa")!)
        XCTAssertEqual(entry.meanings.count, 4)
        XCTAssertEqual(entry.preview.count, 2)
        XCTAssertEqual(entry.meanings[0].examples.count, 2)
        XCTAssertEqual(entry.preview[0].examples, ["Example one."])
        XCTAssertEqual(entry.preview[1].examples.count, 1)
        XCTAssertEqual(entry.meanings[0].definition, "First & meaning.")
        XCTAssertFalse(entry.meanings.contains { $0.definition.contains("Advertisement") })
        XCTAssertThrowsError(try DictionaryService.parse("<h1>Access denied</h1>", source: entry.source))
    }
    func testLookupDoesNotSendFullParagraphAndEncodesPath() throws {
        XCTAssertThrowsError(try DictionaryService.sourceURL(String(repeating: "long paragraph ", count: 20)))
        let url = try DictionaryService.sourceURL(" a/b?x=1 ")
        XCTAssertEqual(url.host, "izoh.uz")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query)
        XCTAssertEqual(try DictionaryService.normalizedQuery(" ÖZBEKÇA "), "o‘zbekcha")
    }
    func testAutomaticLookupUsesSelectionOrCaretWordAndKeepsUzbekApostrophes() {
        let text = "Old paragraph.\n\nYangi jamoa va shamg'alar."
        XCTAssertEqual(DictionaryService.query(in: text, selection: NSRange(location: (text as NSString).length, length: 0)), "shamg'alar")
        let selection = (text as NSString).range(of: "Yangi jamoa")
        XCTAssertEqual(DictionaryService.query(in: text, selection: selection), "Yangi jamoa")
        XCTAssertEqual(DictionaryService.query(in: "jamoa", selection: NSRange(location: 5, length: 0)), "jamoa")
        XCTAssertEqual(DictionaryService.query(in: "", selection: NSRange(location: 0, length: 0)), "")
    }
    func testDocumentCleanupPreservesBreaksAndIndentation() {
        let original = "  O'zbekcha   matn.  \n\n\tIkkinchi\t\tqator.\n"
        let clean = DocumentCleanup.clean(original)
        XCTAssertEqual(clean, "  O'zbekcha matn.\n\n\tIkkinchi qator.\n")
        XCTAssertEqual(DocumentCleanup.clean(clean), clean)
        let stats = DocumentStatistics("Birinchi gap.\n\nIkkinchi gap.")
        XCTAssertEqual(stats.words, 4); XCTAssertEqual(stats.paragraphs, 2)
    }
}

private final class MockServiceProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else { return }
        let (status, body) = handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/x-ndjson"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ServiceTransportTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockServiceProtocol.self]
        return URLSession(configuration: config)
    }
    func testTranslationTransportUsesContractAndCompletes() async throws {
        MockServiceProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/translate/text")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Token"), "fixture-key")
            return (200, "{\"start\":true}\n{\"delta\":\"Hello.\\n\\nWorld.\"}\n{\"done\":true}\n")
        }
        let session = session(); defer { session.invalidateAndCancel(); MockServiceProtocol.handler = nil }
        let config = try TranslationConfiguration(baseURL: "https://fixture.example", token: "fixture-key")
        let output = try await TranslationService.translate("Salom.\n\nDunyo.", direction: .uzEn, configuration: config, session: session) { _ in }
        XCTAssertEqual(output, "Hello.\n\nWorld.")
    }
    func testTruncatedStreamAndUnauthorizedAreNotSuccessfulResults() async throws {
        let session = session(); defer { session.invalidateAndCancel(); MockServiceProtocol.handler = nil }
        let config = try TranslationConfiguration(baseURL: "https://fixture.example", token: "fixture-key")
        for (status, body) in [(200, "{\"delta\":\"Partial\"}\n"), (401, "private error detail") ] {
            MockServiceProtocol.handler = { _ in (status, body) }
            do {
                _ = try await TranslationService.translate("Salom", direction: .uzEn, configuration: config, session: session) { _ in }
                XCTFail("An incomplete or rejected request must fail")
            } catch { XCTAssertFalse(error.localizedDescription.contains("private error detail")) }
        }
    }
}
