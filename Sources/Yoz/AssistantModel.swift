import AppKit
import SwiftUI
import Security
import AssistantCore
import TransliterationCore

enum WritingTool: String, CaseIterable, Identifiable {
    case format = "Format", translate = "Translate", dictionary = "Izohchi", document = "Document"
    var id: String { rawValue }
    var icon: String {
        switch self { case .format: return "textformat"; case .translate: return "globe"; case .dictionary: return "character.book.closed"; case .document: return "doc.text" }
    }
}

/// Per-user credentials live outside the app bundle and source control.
final class ServiceSettings: ObservableObject {
    @Published var url = UserDefaults.standard.string(forKey: "translationURL") ?? "" {
        didSet {
            let old = URLComponents(string: oldValue), new = URLComponents(string: url)
            if old?.host != new?.host || old?.port != new?.port || old?.scheme != new?.scheme { allowInsecureHTTP = false }
        }
    }
    @Published var allowInsecureHTTP = UserDefaults.standard.bool(forKey: "translationAllowHTTP")
    @Published var token = ""
    @Published var notice = ""
    init(loadStoredCredentials: Bool = true) {
        guard loadStoredCredentials else { return }
        let env = ProcessInfo.processInfo.environment
        if let value = env["TRANSLATION_API_KEY"] { token = value }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "uz.yoz.translation", kSecAttrAccount as String: "api-token",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if token.isEmpty, SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            token = String(data: data, encoding: .utf8) ?? ""
        }
        if let value = env["TRANSLATION_API_URL"] { url = value }
        if let value = env["TRANSLATION_API_KEY"] { token = value }
        if let value = env["TRANSLATION_ALLOW_INSECURE_HTTP"] { allowInsecureHTTP = value == "true" }
        if let index = CommandLine.arguments.firstIndex(of: "--import-env"), CommandLine.arguments.count > index + 1 {
            importEnvironment(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
    }
    func importEnvironment(_ file: URL) {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { notice = "Could not read the configuration file."; return }
        for line in content.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if name == "TRANSLATION_API_URL" { url = value }
            if name == "TRANSLATION_API_KEY" { token = value }
            if name == "TRANSLATION_ALLOW_INSECURE_HTTP" { allowInsecureHTTP = value == "true" }
        }
        save()
    }
    func save() {
        do { _ = try configuration() } catch { notice = error.localizedDescription; return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "uz.yoz.translation", kSecAttrAccount as String: "api-token"]
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        let result: OSStatus
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            result = SecItemAdd(item as CFDictionary, nil)
        } else { result = status }
        guard result == errSecSuccess else { notice = "Keychain could not save the API key (\(result))."; return }
        UserDefaults.standard.set(url, forKey: "translationURL")
        UserDefaults.standard.set(allowInsecureHTTP, forKey: "translationAllowHTTP")
        notice = "Saved. The API key is stored in your Mac’s Keychain."
    }
    func configuration() throws -> TranslationConfiguration { try TranslationConfiguration(baseURL: url, token: token, allowInsecureHTTP: allowInsecureHTTP) }
}

private struct PreparedResult {
    var text = ""
    var entry: DictionaryEntry?
    var busy = false
    var error = ""
}

final class AssistantModel: ObservableObject {
    @Published var visible = false
    @Published var details = false
    @Published var editing = false
    @Published var tool: WritingTool = .format
    @Published var defaultTool: WritingTool {
        didSet {
            preferences.set(defaultTool.rawValue, forKey: "defaultWritingTool")
            if !visible { tool = defaultTool; cancelUnneededWork(); prepareRequestedTools() }
        }
    }
    @Published var direction: TranslationDirection = .uzEn {
        didSet {
            if oldValue != direction {
                cancelWork(for: .translate); prepared[.translate] = nil
                if automaticEnabled, preparedForInput == input, requestedTools.contains(.translate) { prepareTranslation() }
            }
        }
    }
    @Published var input = "" {
        didSet { if oldValue != input { resetResult(); if editing { scheduleManualPreparation() } } }
    }
    @Published private var prepared: [WritingTool: PreparedResult] = [:]
    @Published var waitingForPause = false
    @Published var sourceName = "Current draft"
    @Published var scope = "Entire draft"
    @Published var appliedNotice = ""
    let settings: ServiceSettings
    private let pauseDelay: TimeInterval
    private let session: URLSession
    private let preferences: UserDefaults
    private var pendingPreparation: DispatchWorkItem?
    private var tasks: [WritingTool: Task<Void, Never>] = [:]
    private var generation = UUID()
    private var requestIDs: [WritingTool: UUID] = [:]
    private var context: TypingMonitor.Input?
    private var preparedForInput: String?
    private var appliedDraft: (input: TypingMonitor.Input, text: String)?
    private var dictionaryQuery = ""
    private var cache: [String: (Date, DictionaryEntry)] = [:]
    weak var app: AppModel?
    var automaticTranslationAllowed: (() -> Bool)?
    var resize: (() -> Void)?
    var requestEditing: (() -> Void)?
    var returnToEditor: ((TypingMonitor.Input, String) -> Void)?

    init(settings: ServiceSettings = ServiceSettings(), session: URLSession? = nil, pauseDelay: TimeInterval = 0.65, preferences: UserDefaults = .standard) {
        self.settings = settings; self.pauseDelay = pauseDelay
        self.preferences = preferences
        let preferred = preferences.string(forKey: "defaultWritingTool").flatMap(WritingTool.init(rawValue:)) ?? .format
        defaultTool = preferred; tool = preferred
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 120
        self.session = session ?? URLSession(configuration: config, delegate: SameOriginRedirects(), delegateQueue: nil)
    }
    deinit { pendingPreparation?.cancel(); tasks.values.forEach { $0.cancel() }; session.invalidateAndCancel() }
    private var automaticEnabled: Bool { automaticTranslationAllowed?() ?? (app?.enabled == true) }
    var followsDraft: Bool { !editing }
    var output: String { prepared[tool]?.text ?? "" }
    var entry: DictionaryEntry? {
        get { prepared[tool]?.entry }
        set { var result = prepared[tool] ?? PreparedResult(); result.entry = newValue; prepared[tool] = result }
    }
    var busy: Bool { prepared[tool]?.busy == true }
    var anyBusy: Bool { prepared.values.contains { $0.busy } }
    var error: String {
        get { prepared[tool]?.error ?? "" }
        set { var result = prepared[tool] ?? PreparedResult(); result.error = newValue; prepared[tool] = result }
    }
    var canApply: Bool { !waitingForPause && !busy && !output.isEmpty && output != input && context != nil && !editing && preparedForInput == input }
    var statistics: DocumentStatistics { DocumentStatistics(input) }
    private var requestedTools: Set<WritingTool> { visible ? [tool] : [defaultTool] }

    func open(capture: Bool = true) {
        app?.assistantActive = true; visible = true
        if capture, !editing {
            if let draft = app?.monitor?.captureDraft(), sameDraft(draft), preparedForInput == draft.text {
                context = draft
                updateDictionaryQuery(for: draft)
            } else { app?.monitor?.assistantModeChanged() }
        }
        prepareRequestedTools()
        resize?()
    }
    func refresh() {
        if editing { resetResult(); scheduleManualPreparation() }
        else { resetResult(); context = nil; app?.monitor?.assistantModeChanged() }
    }
    func choose(_ tool: WritingTool) {
        guard self.tool != tool else { prepareRequestedTools(); return }
        self.tool = tool; details = false; appliedNotice = ""; resize?()
        cancelUnneededWork(); prepareRequestedTools()
    }
    func resetResult() {
        pendingPreparation?.cancel(); pendingPreparation = nil
        tasks.values.forEach { $0.cancel() }; tasks.removeAll()
        generation = UUID(); requestIDs.removeAll(); prepared.removeAll()
        preparedForInput = nil; waitingForPause = false; appliedNotice = ""
    }
    func close() {
        if editing { resetResult(); input = ""; context = nil }
        visible = false; details = false; editing = false
        tool = defaultTool; cancelUnneededWork(); prepareRequestedTools()
        app?.assistantActive = false; resize?()
    }
    func edit() {
        context = nil; sourceName = "Manual input"; scope = "Copy result"
        editing = true; details = true; resize?(); requestEditing?(); scheduleManualPreparation()
    }
    private func scheduleManualPreparation() {
        guard visible, editing, automaticEnabled, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        waitingForPause = true
        let id = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == id, self.visible, self.editing, self.automaticEnabled else { return }
            self.run()
        }
        pendingPreparation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + pauseDelay, execute: work)
    }
    func draftWillChange(resetApplied: Bool = true) {
        guard followsDraft else { return }
        if resetApplied { appliedDraft = nil }
        pendingPreparation?.cancel(); pendingPreparation = nil
        tasks.values.forEach { $0.cancel() }; tasks.removeAll()
        generation = UUID(); requestIDs.removeAll()
        // Keep completed results hidden until the new snapshot is known. A
        // caret-only change can then reuse translation without another request.
        prepared = prepared.filter { !$0.value.busy }
        context = nil; waitingForPause = true; appliedNotice = ""
    }
    private func sameDraft(_ draft: TypingMonitor.Input) -> Bool {
        guard let current = context else { return false }
        return current.pid == draft.pid && CFEqual(current.element, draft.element) && input == draft.text
    }
    func receiveStableDraft(_ draft: TypingMonitor.Input) {
        guard followsDraft, automaticEnabled else { return }
        if let appliedDraft, appliedDraft.input.pid == draft.pid,
           CFEqual(appliedDraft.input.element, draft.element), appliedDraft.text == draft.text {
            waitingForPause = false; return
        }
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { clearLiveDraft(); return }
        if preparedForInput == draft.text {
            context = draft; waitingForPause = false; updateDictionaryQuery(for: draft)
            prepareRequestedTools()
            return
        }
        resetResult(); context = draft; input = draft.text
        sourceName = NSRunningApplication(processIdentifier: draft.pid)?.localizedName ?? "Current draft"
        scope = "Entire draft"
        prepareSnapshot()
    }
    func clearLiveDraft() {
        guard followsDraft else { return }
        if context != nil || anyBusy || waitingForPause || !input.isEmpty || !prepared.isEmpty {
            resetResult(); context = nil; input = ""
        }
    }
    func stopWork() { resetResult(); context = nil }
    /// Used for manual input and diagnostics; normal drafts arrive after the
    /// monitor's pause detector and are processed whether the widget is open.
    func run() { resetResult(); prepareSnapshot() }
    private func prepareSnapshot() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        preparedForInput = input; waitingForPause = false
        dictionaryQuery = DictionaryService.query(in: input, selection: context.map { NSRange(location: $0.caret.location, length: $0.caret.length) })
        prepareRequestedTools()
    }
    private func prepareRequestedTools() {
        guard preparedForInput == input, !waitingForPause, !input.isEmpty else { return }
        for tool in requestedTools where prepared[tool] == nil {
            switch tool {
            case .format: prepared[tool] = PreparedResult(text: Transliterator.convert(input))
            case .document: prepared[tool] = PreparedResult(text: DocumentCleanup.clean(input))
            case .translate: if automaticEnabled { prepareTranslation() }
            case .dictionary: if automaticEnabled { prepareDictionary() }
            }
        }
    }
    private func cancelWork(for tool: WritingTool) {
        tasks.removeValue(forKey: tool)?.cancel(); requestIDs[tool] = nil
        if prepared[tool]?.busy == true { prepared[tool] = nil }
    }
    private func cancelUnneededWork() {
        for tool in WritingTool.allCases where !requestedTools.contains(tool) { cancelWork(for: tool) }
    }
    private func updateDictionaryQuery(for draft: TypingMonitor.Input) {
        let query = DictionaryService.query(in: draft.text, selection: NSRange(location: draft.caret.location, length: draft.caret.length))
        if query != dictionaryQuery {
            dictionaryQuery = query; cancelWork(for: .dictionary); prepared[.dictionary] = nil
            if automaticEnabled, requestedTools.contains(.dictionary) { prepareDictionary() }
        }
    }
    private func begin(_ tool: WritingTool) -> (UUID, UUID) {
        tasks[tool]?.cancel()
        let id = UUID(); requestIDs[tool] = id
        prepared[tool] = PreparedResult(busy: true)
        return (generation, id)
    }
    private func isCurrent(_ tool: WritingTool, _ ticket: (UUID, UUID)) -> Bool { generation == ticket.0 && requestIDs[tool] == ticket.1 }
    private func prepareTranslation() {
        let ticket = begin(.translate), text = input, direction = direction
        do {
            let config = try settings.configuration()
            _ = try config.request(text: text, direction: direction)
            tasks[.translate] = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let result = try await TranslationService.translate(text, direction: direction, configuration: config, session: session) { [weak self] partial in
                        await MainActor.run {
                            guard let self, self.isCurrent(.translate, ticket) else { return }
                            self.prepared[.translate] = PreparedResult(text: partial, busy: true)
                        }
                    }
                    guard !Task.isCancelled, isCurrent(.translate, ticket) else { return }
                    prepared[.translate] = PreparedResult(text: result)
                } catch { finish(error, tool: .translate, ticket: ticket) }
            }
        } catch { finish(error, tool: .translate, ticket: ticket) }
    }
    private func prepareDictionary() {
        let ticket = begin(.dictionary)
        do {
            let query = try DictionaryService.normalizedQuery(dictionaryQuery)
            if let cached = cache[query], Date().timeIntervalSince(cached.0) < 600 {
                prepared[.dictionary] = PreparedResult(entry: cached.1); return
            }
            tasks[.dictionary] = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let result = try await DictionaryService.lookup(query, session: session)
                    guard !Task.isCancelled, isCurrent(.dictionary, ticket) else { return }
                    if cache.count >= 40 { cache.removeAll() }
                    cache[query] = (Date(), result)
                    prepared[.dictionary] = PreparedResult(entry: result)
                } catch { finish(error, tool: .dictionary, ticket: ticket) }
            }
        } catch { finish(error, tool: .dictionary, ticket: ticket) }
    }
    private func finish(_ error: Error, tool: WritingTool, ticket: (UUID, UUID)) {
        guard isCurrent(tool, ticket) else { return }
        if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { prepared[tool] = PreparedResult(); return }
        let message: String
        if [NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate].contains((error as NSError).code) {
            message = "The service could not establish HTTPS. Check its URL and TLS configuration in Settings."
        } else { message = (error as? AssistantError)?.localizedDescription ?? "Could not reach the source. Check the connection and refresh to retry." }
        prepared[tool] = PreparedResult(error: message)
    }
    func apply() {
        guard canApply, let context else { return }
        appliedDraft = (context, output); returnToEditor?(context, output)
    }
    func copy() {
        guard !busy, !waitingForPause else { return }
        let text = entry.map { item in item.word + "\n\n" + item.meanings.enumerated().map { "\($0.offset + 1). \($0.element.definition)" }.joined(separator: "\n") + "\n\n" + item.source.absoluteString } ?? output
        guard !text.isEmpty else { return }; app?.copy(text); appliedNotice = "Copied"
    }
}

/// Never forward an API credential through a cross-origin redirect.
private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let from = task.originalRequest?.url, let to = request.url,
              from.scheme == to.scheme, from.host == to.host, from.port == to.port else { completionHandler(nil); return }
        completionHandler(request)
    }
}
