import AppKit
import SwiftUI
import Combine
import TransliterationCore

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
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // AppKit otherwise clamps the window below the menu bar, even when the
    // requested frame is at screen.frame.maxY. See ClaudexBar's IslandPanel.
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
    private var statusMenu: NSMenu!
    private var menuClick: DispatchWorkItem?
    private var previewing = false
    private var previewToken: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Design.registerFonts()
        makeMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1070, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Yoz"
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
        statusItem.button?.toolTip = "Yoz · Uzbek transliteration"
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Yoz", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Pause / resume", action: #selector(toggleEnabled), keyEquivalent: "")
        menu.addItem(withTitle: "Preview notch", action: #selector(preview), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Yoz", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusMenu = menu
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        model.$enabled.removeDuplicates().sink { [weak self] enabled in
            self?.statusItem.button?.appearsDisabled = !enabled
            self?.statusItem.button?.toolTip = enabled ? "Yoz on · double-click to pause" : "Yoz paused · double-click to enable"
        }.store(in: &subscriptions)
        model.monitor = TypingMonitor(model: model)
        if CommandLine.arguments.contains("--diagnostics") {
            // Development-only output: status/app names, never the user's text.
            model.$liveStatus.removeDuplicates().sink { status in
                print("YOZ LIVE: \(status)")
                fflush(stdout)
            }.store(in: &subscriptions)
        }
        model.previewBar = { [weak self] in self?.preview() }
        Publishers.CombineLatest4(model.$suggestion, model.$isTyping, model.$enabled, model.$accessibilityGranted)
            .debounce(for: .milliseconds(12), scheduler: RunLoop.main).sink { [weak self] suggestion, typing, enabled, trusted in
            guard let self, !self.previewing else { return }
            guard enabled && trusted else { self.panel.orderOut(nil); return }
            if let suggestion, !typing {
                self.showBar(original: suggestion.original, replacement: suggestion.replacement, preview: false)
            } else { self.showActivity(typing: typing) }
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
        appMenu.addItem(withTitle: "About Yoz", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Yoz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        panel.title = "Yoz Notch"
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
        transitionID += 1
        let id = transitionID
        let animate = panel.isVisible && panel.screen == screen
        let metrics = notchMetrics(screen)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
        notch.reducedMotion = reduced
        // Extra transparent room lets the spring finish without clipping. Both
        // target widths differ by 22 pt, so their native pixel rounding agrees.
        let previous = CGRect(x: metrics.center - notch.width / 2, y: frame.maxY - notch.height,
                              width: notch.width, height: notch.height)
        let union = animate ? previous.union(frame) : frame
        let canvas = animate && !reduced
            ? CGRect(x: union.minX - 10, y: union.minY - 16, width: union.width + 20, height: union.height + 16)
            : union
        panel.setFrame(canvas, display: true)
        let offset = metrics.center - panel.frame.midX
        if abs(notch.contentOffsetX - offset) > 0.01 {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { notch.contentOffsetX = offset }
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        let settle = { [weak self] in
            guard let self, self.transitionID == id else { return }
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
                : .spring(response: mode == "expanded" ? 0.46 : 0.34, dampingFraction: mode == "expanded" ? 0.84 : 0.92)
            if #available(macOS 14.0, *) {
                withAnimation(animation, completionCriteria: .removed, changes, completion: settle)
            } else {
                withAnimation(animation, changes)
                DispatchQueue.main.asyncAfter(deadline: .now() + (reduced ? 0.2 : 0.9), execute: settle)
            }
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
        else if model.enabled && model.accessibilityGranted { showActivity(typing: model.isTyping) }
        else { panel.orderOut(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func capturePanel(to path: String) {
        guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        let layout = NotchLayout(notchWidth: notch.notchWidth)
        let report: [String: Any] = ["frameX": panel.frame.minX, "frameY": panel.frame.minY,
                                   "width": panel.frame.width, "height": panel.frame.height,
                                   "scale": panel.backingScaleFactor, "offsetX": notch.contentOffsetX,
                                   "bodyWidth": notch.width, "bodyContentWidth": notch.contentWidth,
                                   "bodyInset": layout.bodyInset(in: notch.width), "safeTop": notch.safeTop]
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
