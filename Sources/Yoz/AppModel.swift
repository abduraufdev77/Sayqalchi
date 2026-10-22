import AppKit
import SwiftUI
import ApplicationServices
import TransliterationCore

final class AppModel: ObservableObject {
    @Published var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled"); monitor?.enabledChanged() }
    }
    @Published var automatic = UserDefaults.standard.bool(forKey: "automaticFullText") {
        didSet { UserDefaults.standard.set(automatic, forKey: "automaticFullText") }
    }
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var shortcutReady = false
    @Published var suggestion: WordSuggestion?
    @Published var isTyping = false
    @Published var suggestionScope = "Entire draft"
    @Published var activeApp = "Your apps"
    @Published var convertedCount = 0
    @Published var lastNotice = ""
    @Published var liveStatus = "Waiting for a text field in another app"
    @Published var section: AppSection = .overview
    @Published var excludedApps: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []) {
        didSet { UserDefaults.standard.set(Array(excludedApps).sorted(), forKey: "excludedApps") }
    }
    let assistant = AssistantModel()
    var assistantActive = false
    var assistantAccept: (() -> Void)?
    var assistantDismiss: (() -> Void)?
    var monitor: TypingMonitor?
    var openAssistant: (() -> Void)?
    var previewBar: (() -> Void)?
    var status: String { !enabled ? "Paused" : accessibilityGranted ? "Ready to write" : "Accessibility needed" }

    func openPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        monitor?.refreshPermissions()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}

enum AppSection: String, CaseIterable {
    case overview = "Overview", playground = "Playground", alphabet = "The alphabet", settings = "Settings"
    var icon: String {
        switch self { case .overview: return "square.grid.2x2"; case .playground: return "text.cursor"; case .alphabet: return "character.book.closed"; case .settings: return "slider.horizontal.3" }
    }
}
