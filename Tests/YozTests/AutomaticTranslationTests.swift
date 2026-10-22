import XCTest
import AppKit
import AssistantCore
@testable import Yoz

private final class AutomaticTranslationProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var stored: [URLRequest] = []
    static var responseDelay: TimeInterval = 0
    private var stopped = false
    static var allRequests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return stored }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return stored.filter { $0.url?.path == "/api/translate/text" } }
    static func reset() { lock.lock(); stored = []; responseDelay = 0; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.stored.append(request); let delay = Self.responseDelay; Self.lock.unlock()
        let body = Self.body(request)
        let text = body["text"] ?? ""
        let event = try! JSONSerialization.data(withJSONObject: ["delta": "Translated: " + text])
        let complete = request.url?.path == "/api/translate/text"
            ? event + Data("\n{\"done\":true}\n".utf8)
            : Data("<h1 itemprop='name'>jamoa</h1><div id='def-fixture'><p class='font-bold'>A group.</p></div>".utf8)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped else { return }
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/x-ndjson"])!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: complete)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stopped = true }
    static func body(_ request: URLRequest) -> [String: String] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String:String]) ?? [:]
    }
}

@MainActor
final class AutomaticTranslationTests: XCTestCase {
    private func assistant() -> AssistantModel {
        AutomaticTranslationProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AutomaticTranslationProtocol.self]
        let settings = ServiceSettings(loadStoredCredentials: false)
        settings.url = "https://translation.fixture.example"; settings.token = "fixture-only"
        let preferences = UserDefaults(suiteName: "YozTests." + UUID().uuidString)!
        let assistant = AssistantModel(settings: settings, session: URLSession(configuration: config), pauseDelay: 0.06, preferences: preferences)
        assistant.automaticTranslationAllowed = { true }
        assistant.defaultTool = .translate
        assistant.visible = true; assistant.choose(.translate)
        return assistant
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 { if predicate() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("Expected automatic translation state was not reached")
    }
    func testManualTypingDebouncesAndSendsLatestWholeDraft() async throws {
        let model = assistant(); model.edit()
        model.input = "First paragraph."
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(AutomaticTranslationProtocol.requests.isEmpty)
        model.input = "First paragraph.\n\nSecond paragraph."
        try await waitUntil { !model.output.isEmpty && !model.busy }
        XCTAssertEqual(AutomaticTranslationProtocol.requests.count, 1)
        XCTAssertEqual(model.output, "Translated: First paragraph.\n\nSecond paragraph.")
        XCTAssertFalse(model.canApply, "Manual text cannot replace another editor")
        model.close()
    }
    func testStableExternalDraftStartsWithoutRunButtonAndDeduplicates() async throws {
        let model = assistant()
        let element = AXUIElementCreateApplication(getpid())
        let draft = TypingMonitor.Input(element: element, pid: getpid(), caret: CFRange(location: 3, length: 0), text: "One.\n\nTwo.")
        model.receiveStableDraft(draft); model.receiveStableDraft(draft)
        try await waitUntil { !model.output.isEmpty && !model.busy }
        model.receiveStableDraft(draft)
        XCTAssertEqual(AutomaticTranslationProtocol.requests.count, 1)
        XCTAssertEqual(model.output, "Translated: One.\n\nTwo.")
        XCTAssertTrue(model.canApply)
        model.close()
    }
    func testTypingCancelsInFlightResultAndPreventsStaleApply() async throws {
        let model = assistant(); AutomaticTranslationProtocol.responseDelay = 0.18
        let element = AXUIElementCreateApplication(getpid())
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 0, length: 0), text: "Old draft"))
        try await waitUntil { AutomaticTranslationProtocol.requests.count == 1 }
        model.draftWillChange()
        XCTAssertFalse(model.canApply); XCTAssertTrue(model.output.isEmpty)
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 0, length: 0), text: "New draft\n\nAll paragraphs"))
        try await waitUntil { !model.busy && !model.output.isEmpty }
        XCTAssertEqual(model.output, "Translated: New draft\n\nAll paragraphs")
        XCTAssertTrue(model.canApply)
        model.close()
    }
    func testClosingManualInputCancelsPendingPreparation() async throws {
        let model = assistant(); model.edit(); model.input = "Do not send"
        model.close()
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertTrue(AutomaticTranslationProtocol.requests.isEmpty)
    }
    func testLanguageChangeUsesLatestDirectionAfterPause() async throws {
        let model = assistant(); model.edit(); model.input = "Salom"
        model.direction = .uzRu
        try await waitUntil { !model.output.isEmpty && !model.busy }
        XCTAssertEqual(AutomaticTranslationProtocol.requests.count, 1)
        XCTAssertEqual(AutomaticTranslationProtocol.body(AutomaticTranslationProtocol.requests[0])["targetLanguage"], "ru")
        model.close()
    }
    func testPausingYozPreventsPendingAutomaticTransmission() async throws {
        let model = assistant(); var enabled = true
        model.automaticTranslationAllowed = { enabled }
        model.edit(); model.input = "Do not send while paused"; enabled = false
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(AutomaticTranslationProtocol.requests.isEmpty)
        model.close()
    }
    func testApplyingResultDoesNotTranslateTheInsertedTextAgain() async throws {
        let model = assistant(); let element = AXUIElementCreateApplication(getpid())
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 0, length: 0), text: "Original"))
        try await waitUntil { !model.output.isEmpty && !model.busy }
        let translated = model.output
        model.returnToEditor = { [weak model] _, _ in model?.close() }
        model.apply()
        model.draftWillChange(resetApplied: false)
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 0, length: 0), text: translated))
        XCTAssertEqual(AutomaticTranslationProtocol.requests.count, 1)
        XCTAssertFalse(model.visible)
        model.draftWillChange()
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 0, length: 0), text: "New typing"))
        try await waitUntil { !model.output.isEmpty && !model.busy }
        XCTAssertEqual(AutomaticTranslationProtocol.requests.count, 2)
        model.close()
    }

    func testFormatterDefaultDoesNotCallUnopenedServices() async throws {
        let model = assistant(); model.defaultTool = .format; model.close()
        let element = AXUIElementCreateApplication(getpid())
        let draft = TypingMonitor.Input(element: element, pid: getpid(), caret: CFRange(location: 5, length: 0), text: "jamoa")
        model.receiveStableDraft(draft)
        XCTAssertEqual(model.output, "jamoa")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(AutomaticTranslationProtocol.allRequests.isEmpty)
        model.open(capture: false); model.choose(.translate)
        try await waitUntil { !model.busy && !model.output.isEmpty }
        XCTAssertEqual(model.output, "Translated: jamoa")
        XCTAssertEqual(AutomaticTranslationProtocol.allRequests.count, 1)
        model.choose(.format); model.choose(.translate)
        XCTAssertEqual(model.output, "Translated: jamoa")
        XCTAssertEqual(AutomaticTranslationProtocol.requests.count, 1)
        model.choose(.dictionary)
        try await waitUntil { model.entry != nil }
        XCTAssertEqual(AutomaticTranslationProtocol.allRequests.count, 2)
        model.choose(.document); XCTAssertEqual(model.output, "jamoa")
        model.close(); XCTAssertEqual(model.tool, .format)
        model.draftWillChange()
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 4, length: 0), text: "Yangi matn"))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(AutomaticTranslationProtocol.allRequests.count, 2)
        model.stopWork()
    }

    func testLeavingTranslationTabCancelsWorkAndDoesNotRestartItHidden() async throws {
        let model = assistant(); model.defaultTool = .format
        AutomaticTranslationProtocol.responseDelay = 0.2
        let element = AXUIElementCreateApplication(getpid())
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 5, length: 0), text: "jamoa"))
        try await waitUntil { AutomaticTranslationProtocol.requests.count == 1 }
        model.choose(.format)
        XCTAssertFalse(model.anyBusy)
        model.close()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(model.output, "jamoa")
        XCTAssertEqual(AutomaticTranslationProtocol.allRequests.count, 1)
        model.open(capture: false); model.choose(.translate)
        try await waitUntil { !model.busy && !model.output.isEmpty }
        XCTAssertEqual(AutomaticTranslationProtocol.requests.count, 2)
        model.stopWork(); model.close()
    }

    func testDefaultServicePersistsAndOnlyThatServiceRunsWhenCollapsed() async throws {
        let model = assistant(); model.defaultTool = .dictionary; model.close()
        let element = AXUIElementCreateApplication(getpid())
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 5, length: 0), text: "jamoa"))
        try await waitUntil { model.entry != nil }
        XCTAssertTrue(AutomaticTranslationProtocol.requests.isEmpty)
        XCTAssertEqual(AutomaticTranslationProtocol.allRequests.count, 1)
        XCTAssertEqual(model.tool, .dictionary)
        model.choose(.format); model.close()
        XCTAssertEqual(model.defaultTool, .dictionary)
        XCTAssertEqual(model.tool, .dictionary)
        model.stopWork()
        let prefs = UserDefaults(suiteName: "YozTests." + UUID().uuidString)!
        let first = AssistantModel(settings: ServiceSettings(loadStoredCredentials: false), preferences: prefs)
        first.defaultTool = .document
        let second = AssistantModel(settings: ServiceSettings(loadStoredCredentials: false), preferences: prefs)
        XCTAssertEqual(second.defaultTool, .document)
        XCTAssertEqual(second.tool, .document)
    }

    func testFormattedDraftAutomaticallyOpensWithoutHoverAndDismissalSticks() async throws {
        let model = assistant(); model.defaultTool = .format; model.close()
        let element = AXUIElementCreateApplication(getpid())
        let draft = TypingMonitor.Input(element: element, pid: getpid(), caret: CFRange(location: 9, length: 0), text: "O'zbekcha")
        model.receiveStableDraft(draft)
        XCTAssertTrue(model.visible); XCTAssertTrue(model.resultPresented)
        XCTAssertEqual(model.output, "Özbekça"); XCTAssertTrue(model.canApply)
        XCTAssertTrue(AutomaticTranslationProtocol.allRequests.isEmpty)
        model.close()
        model.draftWillChange(resetApplied: false); model.receiveStableDraft(draft)
        XCTAssertFalse(model.visible, "Caret movement must not reopen a dismissed result")
        model.draftWillChange()
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 6, length: 0), text: "shahar"))
        XCTAssertTrue(model.visible); XCTAssertEqual(model.output, "şahar")
        model.stopWork(); model.close()
    }

    func testTranslationOpensOnlyAfterCompletionAndResumedTypingCollapsesIt() async throws {
        let model = assistant(); model.close()
        AutomaticTranslationProtocol.responseDelay = 0.1
        let element = AXUIElementCreateApplication(getpid())
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 5, length: 0), text: "Salom"))
        XCTAssertFalse(model.visible); XCTAssertTrue(model.busy)
        try await waitUntil { model.resultPresented }
        XCTAssertTrue(model.visible); XCTAssertTrue(model.canApply)
        XCTAssertEqual(model.output, "Translated: Salom")
        model.draftWillChange()
        XCTAssertFalse(model.visible); XCTAssertFalse(model.resultPresented); XCTAssertFalse(model.canApply)
        model.stopWork(); model.close()
    }

    func testAutomaticResultStartsCompactAndHoverOrDetailsCanExpandIt() {
        let model = assistant(); model.defaultTool = .format; model.close()
        model.receiveStableDraft(.init(element: AXUIElementCreateApplication(getpid()), pid: getpid(), caret: CFRange(location: 6, length: 0), text: "shahar"))
        XCTAssertTrue(model.compactResult); XCTAssertTrue(model.canApply)
        XCTAssertEqual(model.previewText, "şahar")
        model.browse(true); XCTAssertFalse(model.compactResult)
        model.browse(false); XCTAssertTrue(model.compactResult)
        model.details = true; XCTAssertFalse(model.compactResult)
        model.details = false; XCTAssertTrue(model.compactResult)
        model.draftWillChange(); XCTAssertFalse(model.visible); XCTAssertFalse(model.compactResult)
        model.stopWork(); model.close()
    }

    func testUnchangedFormatterTextDoesNotOpenEmptySuggestion() {
        let model = assistant(); model.defaultTool = .format; model.close()
        model.receiveStableDraft(.init(element: AXUIElementCreateApplication(getpid()), pid: getpid(), caret: CFRange(location: 5, length: 0), text: "Salom"))
        XCTAssertFalse(model.visible); XCTAssertFalse(model.resultPresented); XCTAssertFalse(model.canApply)
        model.stopWork()
    }

    func testCaretMovementKeepsPreparedTranslationWithoutResendingDraft() async throws {
        let model = assistant(); let element = AXUIElementCreateApplication(getpid())
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 5, length: 0), text: "jamoa"))
        try await waitUntil { !model.anyBusy }
        model.draftWillChange(resetApplied: false)
        XCTAssertFalse(model.canApply)
        model.receiveStableDraft(.init(element: element, pid: getpid(), caret: CFRange(location: 2, length: 0), text: "jamoa"))
        XCTAssertEqual(model.output, "Translated: jamoa")
        XCTAssertEqual(AutomaticTranslationProtocol.requests.count, 1)
        model.stopWork(); model.close()
    }

}
