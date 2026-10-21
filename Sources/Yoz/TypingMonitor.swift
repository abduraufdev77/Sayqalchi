import AppKit
import ApplicationServices
import Carbon
import TransliterationCore

final class TypingMonitor {
    weak var model: AppModel?
    private var pendingPoll: DispatchWorkItem?
    private var pollDeadline = TimeInterval.greatestFiniteMagnitude
    private var watchdog: DispatchWorkItem?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var observedEditor: AXUIElement?
    private var stableInput: String?
    private var languagePress = DoublePress()
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var snapshot: Snapshot?
    private var pendingElement: AXUIElement?
    private var pause = TypingPause()
    private var dismissed: String?
    private var applying = false
    private var restorePasteboard: (() -> Void)?
    private var lastTapAttempt = Date.distantPast
    private var preparedPIDs = Set<pid_t>()
    private var lastAXError: AXError = .success
    private let system = AXUIElementCreateSystemWide()

    struct Snapshot {
        let element: AXUIElement
        let pid: pid_t
        let caret: CFRange
        let suggestion: WordSuggestion
        let replacementCaret: Int
    }
    struct Input {
        let element: AXUIElement
        let pid: pid_t
        let caret: CFRange
        let text: String
        var key: String { "\(pid):\(caret.location):\(caret.length):\(text)" }
    }
    init(model: AppModel) {
        self.model = model
        AXUIElementSetMessagingTimeout(system, 0.2)
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.clear()
            if self.model?.enabled == true { self.requestPoll(after: 0.08) }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.suspend(); self?.clear()
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.enabledChanged()
        })
        DispatchQueue.main.async { [weak self] in self?.poll(); self?.armWatchdog() }
    }
    deinit {
        restorePasteboard?()
        suspend()
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
    }
    private func suspend() {
        pendingPoll?.cancel(); pendingPoll = nil; pollDeadline = .greatestFiniteMagnitude
        watchdog?.cancel(); watchdog = nil
    }
    func enabledChanged() {
        suspend(); clear()
        if model?.enabled == true { requestPoll(after: 0); armWatchdog() }
        else { status("Suggestions paused · double-press Right Shift or double-click ö to enable") }
    }
    private func requestPoll(after delay: TimeInterval = 0.08) {
        guard model?.enabled == true else { return }
        let deadline = ProcessInfo.processInfo.systemUptime + delay
        guard deadline < pollDeadline else { return }
        pendingPoll?.cancel(); pollDeadline = deadline
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPoll = nil; self.pollDeadline = .greatestFiniteMagnitude
            self.poll()
        }
        pendingPoll = work; DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func armWatchdog() {
        watchdog?.cancel()
        guard model?.enabled == true else { return }
        let work = DispatchWorkItem { [weak self] in self?.requestPoll(after: 0); self?.armWatchdog() }
        watchdog = work
        // Recovery for custom providers without AX notifications. No rapid idle
        // polling, and no watchdog or editor reads while paused or asleep.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
    private func configureObserver(pid: pid_t) {
        guard observedPID != pid else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; observedEditor = nil; observedPID = pid
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let monitor = Unmanaged<TypingMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.requestPoll()
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        observer = created
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, AXUIElementCreateApplication(pid), kAXFocusedUIElementChangedNotification as CFString, context)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }
    private func observeEditor(_ element: AXUIElement) {
        guard let observer, observedEditor == nil || !CFEqual(observedEditor!, element) else { return }
        for notification in [kAXValueChangedNotification, kAXSelectedTextChangedNotification] {
            if let old = observedEditor { AXObserverRemoveNotification(observer, old, notification as CFString) }
            AXObserverAddNotification(observer, element, notification as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        observedEditor = element
    }
    private func inputActivity() {
        guard model?.enabled == true, !applying else { return }
        stableInput = nil; pause.reset(); hideSuggestion()
        if model?.isTyping != true { model?.isTyping = true }
        requestPoll()
    }
    private func status(_ message: String) { if model?.liveStatus != message { model?.liveStatus = message } }

    func poll() {
        guard let model else { return }
        let trusted = AXIsProcessTrusted()
        if model.accessibilityGranted != trusted { model.accessibilityGranted = trusted }
        if trusted, tap == nil, Date().timeIntervalSince(lastTapAttempt) > 3 { lastTapAttempt = Date(); installShortcut() }
        guard model.enabled else { status("Suggestions paused"); clear(); return }
        guard trusted else { status("macOS has not granted this build Accessibility access"); clear(); return }
        guard !applying else { return }
        guard !IsSecureEventInputEnabled() else { status("macOS Secure Input is active; suggestions paused"); clear(); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { status("Waiting for an app"); clear(); return }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { clear(); return }
        let name = app.localizedName ?? "Current app"
        if model.activeApp != name { model.activeApp = name }
        guard !model.excludedApps.contains(app.bundleIdentifier ?? ""),
              !["com.apple.Terminal", "com.googlecode.iterm2", "com.agilebits.onepassword7", "com.1password.1password"].contains(app.bundleIdentifier ?? "") else {
            status("\(name) is excluded"); clear(); return
        }
        configureObserver(pid: app.processIdentifier)
        if preparedPIDs.insert(app.processIdentifier).inserted {
            // Chromium/Electron expose their full tree lazily to accessibility clients.
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.2)
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        guard let input = readInput(pid: app.processIdentifier, report: true) else { clear(); return }
        observeEditor(input.element)
        if stableInput == input.key, pendingElement.map({ CFEqual($0, input.element) }) == true { return }
        if pendingElement == nil || !CFEqual(pendingElement!, input.element) {
            pause.reset(); dismissed = nil; pendingElement = input.element
        }
        guard dismissed != input.key else { hideSuggestion(); model.isTyping = false; status("Dismissed; edit the text for another suggestion"); return }
        guard pause.ready(key: input.key, now: ProcessInfo.processInfo.systemUptime) else {
            if !model.isTyping { model.isTyping = true }
            hideSuggestion(); status("\(name): waiting for a pause in typing…"); requestPoll(after: 0.67); return
        }
        if model.isTyping { model.isTyping = false }
        stableInput = input.key
        guard let s = proposal(input) else {
            hideSuggestion(); status("\(name): all text already uses the new letters"); return
        }
        snapshot = s
        model.suggestionScope = "Entire draft"
        if model.automatic { accept(); return }
        if model.suggestion != s.suggestion { model.suggestion = s.suggestion }
        status("\(name): suggestion ready — click Use or press ⌥ Return")
    }

    private func protected(_ element: AXUIElement) -> Bool {
        let role = (attribute(element, kAXRoleAttribute) as? String ?? "").lowercased()
        let subrole = (attribute(element, kAXSubroleAttribute) as? String ?? "").lowercased()
        return role.contains("secure") || subrole.contains("secure") || (attribute(element, "AXProtectedContent") as? Bool) == true
    }
    private func editorContent(_ element: AXUIElement) -> EditorScope.Content? {
        guard let selected = selection(element), selected.location >= 0, selected.length >= 0 else { return nil }
        let count = (attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
        let value = attribute(element, kAXValueAttribute) as? String
        // Some rich editors report paragraph-local character counts while their
        // editable root's value contains the complete draft. Prefer that value.
        let text: String
        if let value, (value as NSString).length >= (count ?? 0) { text = value }
        else if let count, count >= 0, count <= 200_000,
                let full = string(element, range: CFRange(location: 0, length: count)),
                (full as NSString).length == count { text = full }
        else { return nil }
        guard (text as NSString).length <= 200_000 else { return nil }
        return EditorScope.Content(text: text, selection: NSRange(location: selected.location, length: selected.length))
    }
    private func readInput(pid: pid_t, report: Bool = false) -> Input? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        for root in [system, app] {
            guard let raw = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { continue }
            let focused = raw as! AXUIElement
            var owner: pid_t = 0
            guard AXUIElementGetPid(focused, &owner) == .success, owner == pid else { continue }
            let resolved = EditorScope.resolve(focused: focused, parent: { element in
                guard let parent = self.attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
                return (parent as! AXUIElement)
            }, inspect: { element in
                if self.protected(element) { return .protected }
                let role = self.attribute(element, kAXRoleAttribute) as? String ?? ""
                if [kAXWindowRole, kAXApplicationRole, "AXWebArea"].contains(role) { return .boundary }
                let explicitEditable = self.attribute(element, "AXEditable") as? Bool
                var settable = DarwinBoolean(false)
                AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
                let textControl = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
                let editable = explicitEditable == true || (textControl && explicitEditable != false)
                    || (CFEqual(element, focused) && settable.boolValue)
                guard editable else { return .container }
                guard (self.attribute(element, kAXEnabledAttribute) as? Bool) != false else { return .protected }
                guard let content = self.editorContent(element) else {
                    return textControl || explicitEditable == true ? .unavailableEditor : .container
                }
                return .editor(content)
            })
            if let resolved {
                guard !resolved.content.text.isEmpty else { break }
                let selection = resolved.content.selection
                return Input(element: resolved.node, pid: pid,
                             caret: CFRange(location: selection.location, length: selection.length),
                             text: resolved.content.text)
            }
        }
        if report { status("\(model?.activeApp ?? "App"): entire editable draft unavailable, empty, protected, or over 200,000 characters") }
        return nil
    }

    private func proposal(_ input: Input) -> Snapshot? {
        guard let s = Transliterator.fieldSuggestion(in: input.text) else { return nil }
        let absolute = WordSuggestion(original: s.original, replacement: s.replacement,
                                      range: NSRange(location: 0, length: s.range.length), atBoundary: true)
        guard let caret = Transliterator.convertedCaret(in: input.text,
                                                        utf16Location: input.caret.location + input.caret.length) else { return nil }
        return Snapshot(element: input.element, pid: input.pid, caret: input.caret, suggestion: absolute, replacementCaret: caret)
    }
    private func readSnapshot(pid: pid_t) -> Snapshot? {
        readInput(pid: pid).flatMap { proposal($0) }
    }

    func accept() {
        guard !applying, !IsSecureEventInputEnabled(), let model, model.enabled, let old = snapshot,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == old.pid,
              let current = readSnapshot(pid: old.pid), CFEqual(current.element, old.element),
              current.caret.location == old.caret.location, current.caret.length == old.caret.length,
              current.suggestion == old.suggestion else { status("Text or focus changed; waiting for a fresh suggestion"); clear(); return }
        var range = CFRange(location: current.suggestion.range.location, length: current.suggestion.range.length)
        guard let axRange = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(current.element, kAXSelectedTextRangeAttribute as CFString, axRange) == .success,
              let actual = selection(current.element), actual.location == range.location, actual.length == range.length else {
            restore(current.caret, in: current.element)
            model.lastNotice = "This field cannot select text for replacement. Use the Playground instead."
            dismiss(); return
        }
        applying = true
        AXUIElementSetAttributeValue(current.element, kAXSelectedTextAttribute as CFString, current.suggestion.replacement as CFString)
        hideSuggestion()
        confirmReplacement(current, stage: 0)
    }
    private func confirmReplacement(_ current: Snapshot, stage: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (stage == 0 ? 0.18 : 0.35)) { [weak self] in
            guard let self, let model = self.model else { return }
            let replacement = current.suggestion.replacement
            let observed = self.editorContent(current.element)
            if observed?.text == replacement {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == current.pid,
                   let now = observed?.selection,
                   (now.location == (replacement as NSString).length && now.length == 0)
                    || (now.location == 0 && now.length == (replacement as NSString).length) {
                    self.restore(CFRange(location: current.replacementCaret, length: 0), in: current.element)
                }
                model.convertedCount += 1
                self.status("Applied to \(model.activeApp)")
                self.restorePasteboard?(); self.restorePasteboard = nil
                self.applying = false; self.clear(); return
            }
            // Some web editors report success for AXSelectedText without editing.
            // Retry only if the complete original draft and its full selection
            // are still unchanged, in the same foreground editor.
            if stage < 1, model.enabled, !IsSecureEventInputEnabled(),
               NSWorkspace.shared.frontmostApplication?.processIdentifier == current.pid,
               let focused = self.readInput(pid: current.pid), CFEqual(focused.element, current.element),
               focused.text == current.suggestion.original,
               focused.caret.location == 0, focused.caret.length == current.suggestion.range.length {
                self.pasteAtomically(replacement, pid: current.pid)
                self.confirmReplacement(current, stage: stage + 1)
                return
            }
            model.lastNotice = "The editor did not confirm replacement. Check the field before trying again."
            self.status("Replacement was not confirmed by the editor")
            self.restorePasteboard?(); self.restorePasteboard = nil
            self.applying = false; self.clear()
        }
    }
    private func pasteAtomically(_ replacement: String, pid: pid_t) {
        // Web contenteditables can ignore AXSelectedText and mis-handle rapid
        // Unicode chunks. One normal paste preserves their input/undo semantics.
        // Preserve all clipboard item types and never overwrite a newer copy.
        let board = NSPasteboard.general
        let previous = (board.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        board.clearContents(); board.setString(replacement, forType: .string)
        // Explicit line-break markup avoids contenteditables turning every
        // plain-text newline into an extra paragraph break on paste.
        let escaped = replacement.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
            .map { "<p style=\"white-space:pre-wrap\">" + $0.replacingOccurrences(of: "\n", with: "<br>") + "</p>" }.joined()
        board.setString("<meta charset=\"utf-8\">" + escaped, forType: .html)
        let written = board.changeCount
        restorePasteboard = {
            guard board.changeCount == written else { return }
            board.clearContents()
            if !previous.isEmpty { board.writeObjects(previous) }
        }
        // Native Select All includes the editable root's block boundaries;
        // an AX text-only range can leave an empty paragraph behind in WebKit.
        for key: CGKeyCode in [0, 9] {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { continue }
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: 0x595A)
                event.postToPid(pid)
            }
        }
    }

    func dismiss() {
        if let snapshot, let input = readInput(pid: snapshot.pid) { dismissed = input.key }
        hideSuggestion()
    }
    private func hideSuggestion() { snapshot = nil; if model?.suggestion != nil { model?.suggestion = nil } }
    func clear() { stableInput = nil; pause.reset(); hideSuggestion(); pause.reset(); pendingElement = nil; if model?.isTyping == true { model?.isTyping = false } }

    private func restore(_ range: CFRange, in element: AXUIElement) {
        var range = range
        if let value = AXValueCreate(.cfRange, &range) { AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) }
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        lastAXError = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard lastAXError == .success else { return nil }
        return value
    }
    private func selection(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }
    private func string(_ element: AXUIElement, range: CFRange) -> String? {
        guard range.location >= 0, range.length >= 0 else { return nil }
        var range = range, value: CFTypeRef?
        if let parameter = AXValueCreate(.cfRange, &range),
           AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
           let text = value as? String { return text }
        guard let text = attribute(element, kAXValueAttribute) as? String else { return nil }
        let ns = text as NSString
        guard ns.length <= 200_000, range.location <= ns.length, range.length <= ns.length - range.location else { return nil }
        return ns.substring(with: NSRange(location: range.location, length: range.length))
    }
    private func installShortcut() {
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<TypingMonitor>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard event.getIntegerValueField(.eventSourceUserData) != 0x595A else { return Unmanaged.passUnretained(event) }
            if type == .flagsChanged {
                let key = event.getIntegerValueField(.keyboardEventKeycode)
                let other = event.flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskSecondaryFn])
                // NX_DEVICELSHIFTKEYMASK: skip chords with the left Shift held.
                if key == 60 && other.isEmpty && event.flags.rawValue & 0x2 == 0 {
                    if monitor.languagePress.update(pressed: event.flags.contains(.maskShift), now: ProcessInfo.processInfo.systemUptime) {
                        DispatchQueue.main.async { monitor.model?.enabled.toggle() }
                    }
                } else { monitor.languagePress.cancel() }
                return Unmanaged.passUnretained(event)
            }
            monitor.languagePress.cancel()
            guard monitor.model?.enabled == true else { return Unmanaged.passUnretained(event) }
            if type != .keyDown {
                DispatchQueue.main.async { monitor.requestPoll() }
                return Unmanaged.passUnretained(event)
            }

            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let modifiers = event.flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])
            if monitor.model?.suggestion != nil, key == 36 && modifiers == .maskAlternate { DispatchQueue.main.async { monitor.accept() }; return nil }
            if monitor.model?.suggestion != nil, key == 53 && modifiers.isEmpty { DispatchQueue.main.async { monitor.dismiss() }; return nil }
            DispatchQueue.main.async { monitor.inputActivity() }
            return Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: [CGEventType.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown].reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }, callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        model?.shortcutReady = tap != nil
    }
}
