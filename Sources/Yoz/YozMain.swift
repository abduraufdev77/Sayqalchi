import AppKit
import SwiftUI
import Combine
import TransliterationCore
import AssistantCore
import ApplicationServices

@main
enum YozMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

final class SuggestionPanel: NSPanel {
    var allowsEditing = false
    override var canBecomeKey: Bool { allowsEditing }
    override var canBecomeMain: Bool { false }
    // AppKit otherwise clamps the window below the menu bar, even when the
    // requested frame is at screen.frame.maxY. Bypass that native frame clamp.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    var window: NSWindow!
    var panel: SuggestionPanel!
    var statusItem: NSStatusItem!
    private var subscriptions = Set<AnyCancellable>()
    private let notch = NotchPresentation()
    private var transitionID = 0
    private var presentedFrame: CGRect?
    private var resizeInFlight = false
    private var statusMenu: NSMenu!
    private var menuClick: DispatchWorkItem?
    private var previewing = false
    private var previewToken: UUID?
    private var hoverWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Design.registerFonts()
        makeMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1070, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Sayqalchi"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(srgbRed: 0.973, green: 0.973, blue: 0.957, alpha: 1)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RootView(model: model))
        window.minSize = NSSize(width: 960, height: 760)
        window.center()
        window.setFrameAutosaveName("YozMainWindow")
        makePanel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "ö"
        statusItem.button?.font = NSFont(name: "Figtree-Regular", size: 19)
        statusItem.button?.toolTip = "Sayqalchi · Writing assistant"
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Sayqalchi", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Pause / resume", action: #selector(toggleEnabled), keyEquivalent: "")
        menu.addItem(withTitle: "Writing tools", action: #selector(openAssistant), keyEquivalent: "")
        menu.addItem(withTitle: "Preview notch", action: #selector(preview), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sayqalchi", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusMenu = menu
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        model.$enabled.removeDuplicates().sink { [weak self] enabled in
            self?.statusItem.button?.appearsDisabled = !enabled
            self?.statusItem.button?.toolTip = enabled ? "Sayqalchi on · double-click to pause" : "Sayqalchi paused · double-click to enable"
        }.store(in: &subscriptions)
        model.monitor = TypingMonitor(model: model)
        let assistant = model.assistant
        assistant.app = model
        assistant.automaticTranslationAllowed = { [weak self] in self?.model.enabled == true && self?.previewing == false }
        assistant.resize = { [weak self] in self?.updateAssistant() }
        assistant.requestEditing = { [weak self] in
            self?.panel.allowsEditing = true
            self?.panel.makeKeyAndOrderFront(nil)
        }
        assistant.returnToEditor = { [weak self] input, text in
            guard let self else { return }
            self.panel.allowsEditing = false; self.panel.resignKey()
            let perform = { [weak self] in
                guard let self else { return }
                if self.model.monitor?.acceptAssistant(input, replacement: text) == true { self.model.assistant.close() }
                else { self.model.assistant.error = "The draft or focus changed. Click your original editor and refresh before applying." }
            }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != input.pid {
                NSRunningApplication(processIdentifier: input.pid)?.activate(options: [])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: perform)
            } else { perform() }
        }
        model.assistantAccept = { [weak assistant] in assistant?.apply() }
        model.assistantDismiss = { [weak assistant] in assistant?.close() }
        assistant.objectWillChange.debounce(for: .milliseconds(16), scheduler: RunLoop.main).sink { [weak self] in self?.updateAssistant() }.store(in: &subscriptions)
        if CommandLine.arguments.contains("--diagnostics") {
            // Development-only output: status/app names, never the user's text.
            model.$liveStatus.removeDuplicates().sink { status in
                print("YOZ LIVE: \(status)")
                fflush(stdout)
            }.store(in: &subscriptions)
        }
        model.openAssistant = { [weak self] in self?.openAssistant() }
        model.previewBar = { [weak self] in self?.preview() }
        Publishers.CombineLatest4(model.$suggestion, model.$isTyping, model.$enabled, model.$accessibilityGranted)
            .debounce(for: .milliseconds(12), scheduler: RunLoop.main).sink { [weak self] suggestion, typing, enabled, trusted in
            guard let self, !self.previewing else { return }
            guard enabled && trusted else {
                if self.model.assistant.visible { self.model.assistant.close() }
                self.panel.orderOut(nil); return
            }
            if self.model.assistant.visible { self.updateAssistant(); return }
            self.showActivity(typing: typing || self.model.assistant.anyBusy)
        }.store(in: &subscriptions)
        if !CommandLine.arguments.contains("--background") { showWindow() }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
            let path = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.snapshot(to: path) }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--notch-snapshot"), CommandLine.arguments.count > i + 1 {
            let path = CommandLine.arguments[i + 1]
            preview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let view = self?.panel.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--notch-gallery"), CommandLine.arguments.count > i + 1 {
            let directory = CommandLine.arguments[i + 1]
            preview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.capturePanel(to: directory + "/notch-preview.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.showActivity(typing: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.capturePanel(to: directory + "/notch-typing.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.preview() }
            for (delay, name) in [(4.03, "start"), (4.18, "middle"), (4.85, "end")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.capturePanel(to: directory + "/notch-transition-" + name + ".png")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.showActivity(typing: false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.capturePanel(to: directory + "/notch-idle.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in self?.endPreview() }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--assistant-gallery"), CommandLine.arguments.count > i + 1 {
            let directory = CommandLine.arguments[i + 1]
            previewing = true
            let assistant = model.assistant
            assistant.open(capture: false)
            assistant.input = "O'zbekcha yozish juda oson.\n\nGo'zal shaharlar va yangi g'oyalar."
            assistant.sourceName = "SAMPLE DRAFT"
            for (delay, action) in [(1.0, "format"), (2.5, "translate"), (4.0, "dictionary"), (5.5, "details"), (7.0, "document")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    switch action {
                    case "format": assistant.choose(.format); assistant.run()
                    case "translate": assistant.choose(.translate)
                    case "dictionary":
                        assistant.choose(.dictionary)
                        if let html = try? String(contentsOfFile: directory + "/dictionary-fixture.html", encoding: .utf8) {
                            assistant.entry = try? DictionaryService.parse(html, source: URL(string: "https://izoh.uz/word/jamoa")!)
                        }
                    case "details": assistant.details = true
                    default: assistant.choose(.document)
                    }
                    self.updateAssistant()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.capturePanel(to: directory + "/assistant-" + action + ".png") }
                }
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--assistant-gallery"), CommandLine.arguments.count > i + 1,
           !CommandLine.arguments.contains("--hold-gallery") {
            let directory = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
                self?.model.assistant.close()
                for (delay, name) in [(0.03, "start"), (0.16, "middle"), (0.32, "late"), (1.1, "end")] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.capturePanel(to: directory + "/assistant-collapse-" + name + ".png")
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self?.previewing = false }
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--auto-assistant-gallery"), CommandLine.arguments.count > i + 1 {
            let directory = CommandLine.arguments[i + 1]
            previewing = true
            model.monitor = nil
            let assistant = model.assistant
            assistant.automaticTranslationAllowed = { true }
            assistant.defaultTool = .format
            let sample = CommandLine.arguments.contains("--short-sample") ? "shahar" : "O'zbekcha yozish oson.\n\nYangi g'oyalar va yaxshi jamoa."
            assistant.receiveStableDraft(.init(element: AXUIElementCreateApplication(getpid()), pid: getpid(), caret: CFRange(location: (sample as NSString).length, length: 0), text: sample))
            assistant.sourceName = "SAMPLE DRAFT"
            Task { @MainActor [weak self] in
                guard let self else { return }
                for _ in 0..<1200 {
                    if !assistant.anyBusy { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                var report: [String: Any] = ["automaticPresentation": ["visible": assistant.visible, "pinned": assistant.resultPresented, "canApply": assistant.canApply]]
                for tool in WritingTool.allCases {
                    assistant.choose(tool)
                    for _ in 0..<1200 {
                        if !assistant.anyBusy { break }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    report[tool.rawValue] = ["output": assistant.output, "error": assistant.error, "meanings": assistant.entry?.meanings.count ?? 0]
                    self.updateAssistant()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self.capturePanel(to: directory + "/auto-" + tool.rawValue.lowercased() + ".png")
                }
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: directory + "/results.json"))
                }
                NSApp.terminate(nil)
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--assistant-live-check"), CommandLine.arguments.count > i + 1 {
            let path = CommandLine.arguments[i + 1]
            Task { @MainActor [weak self] in
                guard let self else { return }
                var report: [String: Any] = [:]
                do {
                    let entry = try await DictionaryService.lookup("jamoa", session: .shared)
                    report["dictionaryMeanings"] = entry.meanings.count
                    report["dictionaryPreviewMeanings"] = entry.preview.count
                    report["dictionaryExamplesPerPreview"] = entry.preview.map { $0.examples.count }
                } catch { report["dictionaryError"] = error.localizedDescription }
                do {
                    let settings = self.model.assistant.settings
                    let text: String
                    if settings.provider == .myMemory {
                        text = try await PublicTranslationService.translate("Salom, dunyo!", direction: .uzEn, session: .shared) { _ in }
                    } else {
                        let config = try settings.configuration()
                        text = try await TranslationService.translate("Salom, dunyo!", direction: .uzEn, configuration: config, session: .shared) { _ in }
                    }
                    report["translationSucceeded"] = !text.isEmpty
                } catch { report["translationSucceeded"] = false; report["translationErrorCode"] = (error as NSError).code }
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--capture-gallery"), CommandLine.arguments.count > i + 1 {
            let directory = CommandLine.arguments[i + 1]
            for (index, section) in AppSection.allCases.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) + 1) { [weak self] in
                    guard let self else { return }
                    self.model.section = section
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.snapshot(to: directory + "/" + section.rawValue.lowercased().replacingOccurrences(of: " ", with: "-") + ".png")
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { NSApp.terminate(nil) }
        }
    }

    private func makeMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Sayqalchi", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Sayqalchi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        for (name, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: name, action: action, keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
    private func makePanel() {
        panel = SuggestionPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 222), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // The island touches the physical display edge and covers the menu bar
        // only within its own silhouette, like a hardware notch extension.
        panel.title = "Sayqalchi Notch"
        panel.isFloatingPanel = true
        // isFloatingPanel resets level: assign the menu-bar overlay level last.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.worksWhenModal = true
        if #available(macOS 14.0, *) { panel.collectionBehavior.insert(.canJoinAllApplications) }
        notch.assistant = model.assistant
        notch.hover = { [weak self] inside in self?.hoverNotch(inside) }
        notch.accept = { [weak self] in self?.model.monitor?.accept() }
        notch.dismiss = { [weak self] in
            guard let self else { return }
            if self.previewing { self.endPreview() } else { self.model.monitor?.dismiss() }
        }
        notch.open = { [weak self] in self?.showWindow() }
        notch.toggle = { [weak self] in self?.toggleEnabled() }
        let host = NotchHostingView(rootView: NotchRootView(state: notch).ignoresSafeArea())
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }
    private func hoverNotch(_ inside: Bool) {
        hoverWork?.cancel()
        guard !previewing, model.enabled, model.accessibilityGranted else { return }
        if inside && (!model.assistant.visible || model.assistant.compactResult) {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.model.assistant.visible { self.model.assistant.browse(true) }
                else { self.model.assistant.open() }
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        } else if !inside && model.assistant.visible && !model.assistant.details && !model.assistant.editing {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.model.assistant.resultPresented { self.model.assistant.browse(false) }
                else { self.model.assistant.close() }
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
        }
    }
    private func updateAssistant() {
        let assistant = model.assistant
        model.assistantActive = assistant.visible
        guard assistant.visible else {
            panel.allowsEditing = false; panel.resignKey()
            if model.enabled && model.accessibilityGranted {
                showActivity(typing: model.isTyping || model.assistant.anyBusy)
            } else { panel.orderOut(nil) }
            return
        }
        let screen = activeScreen(), metrics = notchMetrics(screen)
        let layout = NotchLayout(notchWidth: metrics.width)
        let compact = assistant.compactResult
        let width = min(screen.frame.width - 32, compact ? layout.resultWidth : assistant.details ? 670 : 510)
        let contentWidth = compact ? layout.contentWidth : width - 70
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 2
        let measured = (String(assistant.previewText.prefix(2000)) as NSString).boundingRect(
            with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont(name: "Figtree-Medium", size: 14) ?? NSFont.systemFont(ofSize: 14), .paragraphStyle: paragraph])
        let bodyHeight: CGFloat = compact ? 70 + min(126, max(22, ceil(measured.height)))
            : assistant.details ? min(510, screen.visibleFrame.height - 95) : assistant.tool == .translate ? 235 : 295
        let frame = NotchGeometry.expandedFrame(screen: screen.frame, width: width, contentHeight: bodyHeight + 7,
            safeTop: metrics.safeTop, centerX: metrics.center, backingScale: screen.backingScaleFactor)
        notch.contentWidth = contentWidth; notch.contentHeight = bodyHeight
        notch.safeTop = metrics.safeTop + 1 / screen.backingScaleFactor
        notch.notchWidth = metrics.width
        notch.typing = assistant.anyBusy || (assistant.followsDraft && model.isTyping)
        if !assistant.editing && panel.allowsEditing { panel.allowsEditing = false; panel.resignKey() }
        // Skip the window morph for streaming deltas and ordinary body changes.
        if notch.width == frame.width && notch.height == frame.height && panel.isVisible { return }
        present(frame: frame, screen: screen, mode: "expanded") {
            self.notch.result = false; self.notch.typing = assistant.anyBusy || (assistant.followsDraft && self.model.isTyping); self.notch.settling = false
        }
    }
    private func activeScreen() -> NSScreen {
        // Use the front app's physical screen, including external monitors.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontWindows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let bounds = frontWindows.first { ($0[kCGWindowOwnerPID as String] as? Int32) == frontPID && ($0[kCGWindowLayer as String] as? Int) == 0 }?[kCGWindowBounds as String] as? [String: CGFloat]
        return NSScreen.screens.first { s in
            guard let bounds else { return false }
            let mainHeight = NSScreen.screens.first?.frame.maxY ?? s.frame.maxY
            let center = NSPoint(x: (bounds["X"] ?? 0) + (bounds["Width"] ?? 0) / 2, y: mainHeight - (bounds["Y"] ?? 0) - (bounds["Height"] ?? 0) / 2)
            return s.frame.contains(center)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    private func notchMetrics(_ screen: NSScreen) -> (center: CGFloat, width: CGFloat, safeTop: CGFloat) {
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           (80...400).contains(right.minX - left.maxX) {
            return ((left.maxX + right.minX) / 2, right.minX - left.maxX, screen.safeAreaInsets.top)
        }
        return (screen.frame.midX, 150, 28)
    }
    private func showBar(original: String, replacement: String, preview: Bool) {
        let screen = activeScreen(), metrics = notchMetrics(screen)
        let layout = NotchLayout(notchWidth: metrics.width)
        let width = layout.resultWidth
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 2
        let measured = (String(replacement.prefix(2000)) as NSString).boundingRect(
            with: NSSize(width: layout.contentWidth, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont(name: "Figtree-Medium", size: 14) ?? NSFont.systemFont(ofSize: 14), .paragraphStyle: paragraph])
        let textHeight = min(174, max(28, ceil(measured.height)))
        let frame = NotchGeometry.expandedFrame(screen: screen.frame, width: width, contentHeight: 76 + textHeight, safeTop: metrics.safeTop, centerX: metrics.center, backingScale: screen.backingScaleFactor)
        if notch.result && notch.replacement == replacement && notch.app == model.activeApp && notch.preview == preview && panel.frame == frame { return }
        let runs = Transliterator.runs(in: original)
        let highlighted = runs.reduce(Text("")) { $0 + Text($1.text).foregroundColor($1.changed ? Design.orange : .white) }
        // Freeze the body at its final width; the silhouette grows around it.
        // No disabled-animation transaction may leak into the subsequent morph.
        notch.highlighted = highlighted; notch.replacement = replacement
        notch.app = model.activeApp; notch.preview = preview
        notch.safeTop = metrics.safeTop + 1 / screen.backingScaleFactor
        notch.notchWidth = metrics.width
        notch.contentWidth = layout.contentWidth
        notch.contentHeight = frame.height - notch.safeTop
        present(frame: frame, screen: screen, mode: "expanded") {
            self.notch.result = true; self.notch.typing = false; self.notch.settling = true
        }
    }
    private func showActivity(typing: Bool) {
        let screen = activeScreen(), metrics = notchMetrics(screen)
        let frame = NotchGeometry.compactFrame(screen: screen.frame, notchWidth: metrics.width, safeTop: metrics.safeTop, centerX: metrics.center, backingScale: screen.backingScaleFactor)
        if !notch.result && notch.typing == typing && panel.frame == frame && panel.isVisible { return }
        notch.notchWidth = metrics.width
        notch.safeTop = metrics.safeTop + 1 / screen.backingScaleFactor
        present(frame: frame, screen: screen, mode: typing ? "typing" : "idle") {
            self.notch.result = false; self.notch.typing = typing; self.notch.settling = false
        }
    }
    private func present(frame: CGRect, screen: NSScreen, mode: String, update: () -> Void) {
        // Published assistant changes also deliver a debounced resize. If that
        // repeats an in-flight target, keep its canvas until the morph finishes;
        // rebuilding it from the target size would clip the collapse instantly.
        if panel.isVisible, panel.screen == screen, presentedFrame == frame {
            update()
            return
        }
        presentedFrame = frame
        transitionID += 1
        let id = transitionID
        let animate = panel.isVisible && panel.screen == screen
        let metrics = notchMetrics(screen)
        // A brief resize stays fluid in Low Power Mode; the continuous waveform
        // already pauses there. Respect the explicit Reduce Motion preference.
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        notch.reducedMotion = reduced
        // Extra transparent room lets either direction of the spring finish
        // without clipping the island before its native window is resized.
        let previous = CGRect(x: metrics.center - notch.width / 2, y: frame.maxY - notch.height,
                              width: notch.width, height: notch.height)
        let union = animate ? previous.union(frame) : frame
        let padded = animate && !reduced
            ? CGRect(x: union.minX - 10, y: union.minY - 16, width: union.width + 20, height: union.height + 16)
            : union
        // Reversing a hover mid-animation must also retain the room occupied by
        // the current presentation, rather than just its previous target size.
        let canvas = animate && resizeInFlight ? padded.union(panel.frame) : padded
        resizeInFlight = animate
        panel.setFrame(canvas, display: true)
        let offset = metrics.center - panel.frame.midX
        if abs(notch.contentOffsetX - offset) > 0.01 {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { notch.contentOffsetX = offset }
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        let settle = { [weak self] in
            guard let self, self.transitionID == id else { return }
            self.resizeInFlight = false
            self.panel.setFrame(frame, display: true)
            let offset = metrics.center - self.panel.frame.midX
            if abs(self.notch.contentOffsetX - offset) > 0.01 {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { self.notch.contentOffsetX = offset }
            }
        }
        let changes = {
            self.notch.width = frame.width; self.notch.height = frame.height; update()
        }
        if !animate {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction, changes)
            settle()
        } else {
            let animation: Animation = reduced ? .easeOut(duration: 0.15)
                : .spring(response: 0.46, dampingFraction: mode == "expanded" ? 0.84 : 0.92)
            if #available(macOS 14.0, *) {
                withAnimation(animation, completionCriteria: .removed, changes, completion: settle)
            } else {
                withAnimation(animation, changes)
            }
            // SwiftUI may retain a removed-animation completion while other
            // observed content updates. Bound the transparent native canvas's
            // lifetime; transitionID makes this safe if hover reverses again.
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduced ? 0.2 : 0.9), execute: settle)
        }
        panel.orderFrontRegardless()
        if mode == "expanded" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                guard let self, self.transitionID == id else { return }
                self.notch.settling = false
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--notch-gallery"), CommandLine.arguments.count > i + 1 {
            let actual = panel.frame
            let report: [String: Any] = ["mode": mode, "panelLevel": panel.level.rawValue,
                                       "menuBarLevel": NSWindow.Level.mainMenu.rawValue,
                                       "backingScale": screen.backingScaleFactor,
                                       "screenTop": screen.frame.maxY, "panelTop": actual.maxY,
                                       "topOverscanPixels": (actual.maxY - screen.frame.maxY) * screen.backingScaleFactor,
                                       "width": actual.width, "height": actual.height]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                let path = CommandLine.arguments[i + 1] + "/notch-" + mode + "-layout.json"
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        if CommandLine.arguments.contains("--diagnostics") {
            let overscan = (panel.frame.maxY - screen.frame.maxY) * screen.backingScaleFactor
            print("YOZ NOTCH: \(mode) level=\(panel.level.rawValue) topOverscanPixels=\(overscan) frame=\(panel.frame)")
            fflush(stdout)
        }
    }
    private func openStatusMenu() {
        guard let button = statusItem.button else { return }
        statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 3), in: button)
    }
    @objc private func statusClicked() {
        menuClick?.cancel()
        if NSApp.currentEvent?.type == .rightMouseUp { openStatusMenu(); return }
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { toggleEnabled(); return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.openStatusMenu()
        }
        menuClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    @objc func openAssistant() { model.assistant.open() }
    @objc func showWindow() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func toggleEnabled() { model.enabled.toggle() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func preview() {
        previewing = true
        let token = UUID()
        previewToken = token
        let sample = "O'zbekcha yozish juda oson. Salom, do'stlar!\n\nGo'zal shaharlar va yangi g'oyalar.\nHar bir so'z, har bir satr — yangi alifboda."
        showBar(original: sample, replacement: Transliterator.convert(sample), preview: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.previewToken == token { self?.endPreview() }
        }
    }
    private func endPreview() {
        previewing = false; previewToken = nil
        if let suggestion = model.suggestion { showBar(original: suggestion.original, replacement: suggestion.replacement, preview: false) }
        else if model.enabled && model.accessibilityGranted { showActivity(typing: model.isTyping || model.assistant.anyBusy) }
        else { panel.orderOut(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); model.monitor?.refreshPermissions(); return true
    }
    private func capturePanel(to path: String) {
        guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        let report: [String: Any] = ["frameX": panel.frame.minX, "frameY": panel.frame.minY,
                                   "width": panel.frame.width, "height": panel.frame.height,
                                   "scale": panel.backingScaleFactor, "offsetX": notch.contentOffsetX,
                                   "bodyWidth": notch.width, "bodyContentWidth": notch.contentWidth,
                                   "bodyInset": (notch.width - notch.contentWidth) / 2, "safeTop": notch.safeTop]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: ".json")))
        }
    }
    private func snapshot(to path: String) {
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }
}
