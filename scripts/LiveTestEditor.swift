// Local, unsaved AppKit editor used to validate Yoz across process boundaries.
// This fixture does not automate input, save text, or grant any permission.
import AppKit
import WebKit

final class LiveEditorDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, WKNavigationDelegate {
    var window: NSWindow!
    let editor = NSTextView()
    var richEditor: WKWebView?
    let counter = NSTextField(labelWithString: "0 characters · 0 newlines")
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Live Test", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(); item.submenu = appMenu; menu.addItem(item)
        let edit = NSMenu(title: "Edit")
        for (name, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(withTitle: name, action: action, keyEquivalent: key) }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; menu.addItem(editItem)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 380), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Yoz Live Test — local, unsaved"
        window.appearance = NSAppearance(named: .aqua)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 380))
        let label = NSTextField(labelWithString: "Type a sentence, pause, then click Use in the notch.")
        label.frame = NSRect(x: 24, y: 335, width: 710, height: 24)
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.frame.size.width = 560
        content.addSubview(label)
        let focus = NSButton(title: "Focus draft", target: self, action: #selector(focusDraft))
        focus.frame = NSRect(x: 620, y: 330, width: 115, height: 30)
        content.addSubview(focus)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 55, width: 720, height: 260))
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        editor.frame = scroll.contentView.bounds
        editor.minSize = NSSize(width: 0, height: scroll.contentView.bounds.height)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 24); editor.textColor = .textColor
        editor.textContainerInset = NSSize(width: 16, height: 16)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel("Yoz live test text")
        editor.delegate = self; editor.allowsUndo = true
        if CommandLine.arguments.contains("--seed") {
            editor.string = CommandLine.arguments.contains("--multiline")
                ? "👋 O'zbekcha yozish juda oson.\n\nG'oya va shahar. Chiroyli kun!"
                : "O'zbekcha yozish juda oson. Salom!"
            let caret = CommandLine.arguments.contains("--caret-middle")
                ? (editor.string as NSString).range(of: "\n").location : (editor.string as NSString).length
            editor.setSelectedRange(NSRange(location: caret, length: 0))
            updateStats()
        }
        scroll.documentView = editor; content.addSubview(scroll)
        if CommandLine.arguments.contains("--rich") {
            let web = WKWebView(frame: scroll.frame)
            web.navigationDelegate = self
            web.autoresizingMask = [.width, .height]
            let html = """
            <!doctype html><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
            <style>body{font:19px -apple-system;padding:12px} #draft{border:1px solid #888;padding:14px;min-height:150px}p{margin:0 0 16px}</style>
            <div aria-label="Read-only history">Old shahar history must stay unchanged.</div>
            <div id="draft" contenteditable="true" role="textbox" aria-label="Whole draft test" aria-multiline="true" tabindex="0" autofocus><p>O'zbekistonda yangi loyiha ustida ishlayapmiz. Bu loyiha shahar va qishloqlarda ishlatiladi, uning chiroyli ko'rinishi va qulay boshqaruv oynasi bor.</p><p>Dashboard orqali barcha o'zgarishlarni ko'rish mumkin.</p></div>
            """
            web.loadHTMLString(html, baseURL: nil)
            scroll.isHidden = true; content.addSubview(web); richEditor = web
        }
        counter.frame = NSRect(x: 24, y: 20, width: 710, height: 22); content.addSubview(counter)
        window.contentView = content; window.center(); window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        DispatchQueue.main.async { self.focusDraft() }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window.makeFirstResponder(webView); print("TEST EDITOR activation accepted: \(NSRunningApplication.current.activate(options: [.activateAllWindows]))"); fflush(stdout)
    }
    @objc private func focusDraft() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(richEditor ?? editor)
        print("TEST EDITOR activation accepted: \(NSRunningApplication.current.activate(options: [.activateAllWindows]))"); fflush(stdout)
    }
    private func updateStats() { counter.stringValue = "\(editor.string.count) characters · \(editor.string.filter { $0 == "\n" }.count) newlines · caret \(editor.selectedRange().location)" }
    func textDidChange(_ notification: Notification) { updateStats() }
    func textViewDidChangeSelection(_ notification: Notification) { updateStats() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = LiveEditorDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
withExtendedLifetime(delegate) {}
