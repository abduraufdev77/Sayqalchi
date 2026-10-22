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
    init() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "uz.yoz.translation", kSecAttrAccount as String: "api-token",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            token = String(data: data, encoding: .utf8) ?? ""
        }
        let env = ProcessInfo.processInfo.environment
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

final class AssistantModel: ObservableObject {
    @Published var visible = false
    @Published var details = false
    @Published var editing = false
    @Published var tool: WritingTool = .format
    @Published var direction: TranslationDirection = .uzEn { didSet { if oldValue != direction { resetResult() } } }
    @Published var input = "" { didSet { if oldValue != input { resetResult() } } }
    @Published var output = ""
    @Published var entry: DictionaryEntry?
    @Published var busy = false
    @Published var error = ""
    @Published var sourceName = "Current draft"
    @Published var scope = "Entire draft"
    @Published var appliedNotice = ""
    let settings = ServiceSettings()
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private var context: TypingMonitor.Input?
    private var resultInput = ""
    private var cache: [String: (Date, DictionaryEntry)] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 120
        return URLSession(configuration: config, delegate: SameOriginRedirects(), delegateQueue: nil)
    }()
    weak var app: AppModel?
    var resize: (() -> Void)?
    var requestEditing: (() -> Void)?
    var returnToEditor: ((TypingMonitor.Input, String) -> Void)?

    deinit { task?.cancel(); session.invalidateAndCancel() }

    var canApply: Bool { !busy && !output.isEmpty && context != nil && !editing && input == resultInput && context?.text == input }
    var statistics: DocumentStatistics { DocumentStatistics(input) }
    func open(capture: Bool = true) {
        if capture { refresh() }
        app?.assistantActive = true
        visible = true; resize?()
    }
    func refresh() {
        resetResult(); context = app?.monitor?.captureDraft()
        input = context?.text ?? ""
        sourceName = context.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName } ?? "No editable draft"
        scope = "Entire draft"; editing = false
    }
    func choose(_ tool: WritingTool) {
        guard self.tool != tool else { return }
        resetResult(); self.tool = tool; details = false
        if !editing, tool == .dictionary, let context, context.caret.length > 0 {
            input = (context.text as NSString).substring(with: NSRange(location: context.caret.location, length: context.caret.length))
            scope = "Selected word or phrase"
        } else if !editing, let context { input = context.text; scope = "Entire draft" }
        resize?()
    }
    func resetResult() {
        requestID = UUID(); task?.cancel(); task = nil
        busy = false; output = ""; entry = nil; error = ""; appliedNotice = ""
    }
    func close() { resetResult(); app?.assistantActive = false; visible = false; details = false; editing = false; context = nil; input = ""; resize?() }
    func edit() { context = nil; sourceName = "Manual input"; scope = "Copy result"; editing = true; details = true; resize?(); requestEditing?() }
    func run() {
        resetResult()
        let text = input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = AssistantError.empty.localizedDescription; return }
        resultInput = text
        switch tool {
        case .format: output = Transliterator.convert(text)
        case .document: output = DocumentCleanup.clean(text)
        case .translate:
            do {
                let configuration = try settings.configuration()
                // Validate before starting the request; a long draft is never silently cut.
                _ = try configuration.request(text: text, direction: direction)
                busy = true
                let id = requestID, direction = direction
                task = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let result = try await TranslationService.translate(text, direction: direction, configuration: configuration, session: session) { [weak self] partial in
                            await MainActor.run { if self?.requestID == id { self?.output = partial } }
                        }
                        guard !Task.isCancelled, self.requestID == id else { return }
                        self.output = result; self.busy = false
                    } catch { self.finish(error, id: id) }
                }
            } catch { self.error = error.localizedDescription }
        case .dictionary:
            do {
                let query = try DictionaryService.normalizedQuery(text)
                if let cached = cache[query], Date().timeIntervalSince(cached.0) < 600 { entry = cached.1; return }
                busy = true; let id = requestID
                task = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let result = try await DictionaryService.lookup(query, session: session)
                        guard !Task.isCancelled, self.requestID == id else { return }
                        if self.cache.count >= 40 { self.cache.removeAll() }
                        self.cache[query] = (Date(), result); self.entry = result; self.busy = false; self.resize?()
                    } catch { self.finish(error, id: id) }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func finish(_ error: Error, id: UUID) {
        guard requestID == id else { return }
        busy = false; output = ""
        if !(error is CancellationError), (error as NSError).code != NSURLErrorCancelled {
            // Do not expose server response bodies, request headers or credentials.
            let code = (error as NSError).code
            if [NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate].contains(code) {
                self.error = "The service could not establish HTTPS. Check its URL, port and TLS configuration in Settings."
            } else { self.error = (error as? AssistantError)?.localizedDescription ?? "Could not reach the source. Check the URL and your connection, then retry." }
        }
    }
    func apply() {
        guard canApply, let context else { return }
        returnToEditor?(context, output)
    }
    func copy() {
        guard !busy else { return }
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
