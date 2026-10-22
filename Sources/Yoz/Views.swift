import SwiftUI
import AppKit
import TransliterationCore

struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 205)
            Rectangle().fill(Design.line).frame(width: 1)
            VStack(spacing: 0) {
                HStack {
                    Text(model.section.rawValue).font(Design.font(13, .medium)).foregroundStyle(Design.muted)
                    Spacer()
                    Circle().fill(model.enabled && model.accessibilityGranted ? Design.green : Design.orange).frame(width: 6, height: 6)
                    Text(model.status).font(Design.font(11, .medium))
                    Button { model.enabled.toggle() } label: { Image(systemName: model.enabled ? "pause.fill" : "play.fill").font(.system(size: 10)).frame(width: 27, height: 27).background(Design.line.opacity(0.6), in: Circle()) }
                        .buttonStyle(PointerButtonStyle()).help(model.enabled ? "Pause suggestions" : "Resume suggestions")
                }.padding(.horizontal, 28).frame(height: 60)
                Rectangle().fill(Design.line).frame(height: 1)
                ScrollView {
                    Group {
                        switch model.section {
                        case .overview: OverviewView(model: model)
                        case .playground: PlaygroundView()
                        case .alphabet: AlphabetView()
                        case .settings: SettingsView(model: model)
                        }
                    }.padding(28).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Design.paper)
        }.font(Design.font(14)).foregroundStyle(Design.ink).background(Design.paper)
            .frame(minWidth: 960, minHeight: 730).preferredColorScheme(.light)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) { YozMark(); Text("Yoz").font(Design.font(26, .semibold)).tracking(-1) }.padding(.top, 32).padding(.bottom, 7)
            Text("A little shift in your letters.").font(Design.font(11)).foregroundStyle(Design.muted).padding(.bottom, 38)
            ForEach(AppSection.allCases, id: \.self) { section in
                Button { model.section = section } label: {
                    HStack(spacing: 11) {
                        Image(systemName: section.icon).font(.system(size: 15)).frame(width: 19)
                        Text(section.rawValue).font(Design.font(13, model.section == section ? .semibold : .regular))
                        Spacer()
                        if model.section == section { Circle().fill(Design.cyan).frame(width: 5, height: 5) }
                    }.padding(.horizontal, 12).frame(height: 42)
                        .foregroundStyle(model.section == section ? Design.ink : Design.muted)
                        .background(model.section == section ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(PointerButtonStyle()).padding(.bottom, 4)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 11) {
                HStack { Image(systemName: "lock.shield"); Text("Your writing, your choice").font(Design.font(11, .medium)) }
                Text("Your default tool after a pause.\nOther tools when you choose.").font(Design.font(11)).foregroundStyle(Design.muted).lineSpacing(4)
            }.padding(.bottom, 23)
            Rectangle().fill(Design.line).frame(height: 1)
            HStack { Text("YOZ FOR MAC").tracking(1.5); Spacer(); Text("v0.5.0") }.font(Design.font(9, .medium)).foregroundStyle(Design.muted).padding(.top, 18)
        }.padding(.horizontal, 18).padding(.bottom, 25).background(Color(hex: 0xEFEFEA))
    }
}

struct OverviewView: View {
    @ObservedObject var model: AppModel
    @State private var scenario = "Telegram"
    var body: some View {
        VStack(alignment: .leading, spacing: 27) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 7) { Circle().fill(Design.green).frame(width: 6, height: 6); Text("UZBEK, IN EVERY APP").tracking(1.8).font(Design.font(9, .semibold)) }
                    VStack(alignment: .leading, spacing: -3) {
                        Text("Your words.")
                        Text("A new alphabet.").foregroundStyle(Design.ink)
                    }.font(Design.font(46)).tracking(-1.8).fixedSize(horizontal: true, vertical: false)
                    Text("Write freely. Pause. Review all your new letters\nat the notch, then click Use to replace the text.").font(Design.font(14)).foregroundStyle(Design.muted).lineSpacing(5)
                    HStack(spacing: 10) {
                        ActionButton(title: "Try the Playground", icon: "arrow.up.right") { model.section = .playground }
                        Button("Writing tools") { model.openAssistant?() }.font(Design.font(12, .medium)).buttonStyle(PointerButtonStyle()).padding(.leading, 6)
                    }.padding(.top, 4)
                }
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text("o‘").font(Design.font(42)).foregroundStyle(Design.ink.opacity(0.4))
                    Image(systemName: "arrow.down").font(.system(size: 18)).padding(.vertical, 7)
                    Text("ö").font(Design.font(85)).tracking(-4)
                }.frame(width: 143, height: 212).background(Design.orange, in: RoundedRectangle(cornerRadius: 24)).rotationEffect(.degrees(5))
                    .accessibilityLabel("Old o apostrophe becomes ö")
            }
            DemoSurface(scenario: $scenario)
            HStack(alignment: .center, spacing: 15) {
                Image(systemName: model.accessibilityGranted ? "checkmark.shield" : "hand.raised").font(.system(size: 23, weight: .light)).frame(width: 46, height: 46).background(Design.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.accessibilityGranted ? "You're ready to write." : "One permission. Every app.").font(Design.font(15, .medium))
                    Text(model.accessibilityGranted ? "Pause, hover the notch, and choose a prepared result." : "Enable Accessibility to suggest letters while you type in other apps.").font(Design.font(11)).foregroundStyle(Design.muted)
                }
                Spacer()
                if !model.accessibilityGranted {
                    ActionButton(title: "Enable Accessibility", icon: "arrow.up.right", color: Design.cyan, textColor: Design.ink) { model.openPermissions() }
                } else {
                    Text("CONNECTED").font(Design.font(9, .semibold)).tracking(1).padding(10).background(Design.green.opacity(0.3), in: Capsule())
                }
            }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Design.line))
            HStack {
                Label("Works where you write", systemImage: "macwindow")
                Spacer()
                Text("o‘ → ö     g‘ → ğ     sh → ş     ch → ç").foregroundStyle(Design.ink)
            }.font(Design.font(11)).foregroundStyle(Design.muted)
        }
    }
}

struct DemoSurface: View {
    @Binding var scenario: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach(["Telegram", "Mail", "Browser"], id: \.self) { app in
                    Button { scenario = app } label: { Text(app).font(Design.font(11, .medium)).padding(.horizontal, 15).frame(height: 28).background(scenario == app ? .white : Color.clear, in: Capsule()).foregroundStyle(scenario == app ? Design.ink : Design.muted) }.buttonStyle(PointerButtonStyle())
                }
                Spacer()
                Text("LIVE PREVIEW").font(Design.font(8, .semibold)).tracking(1.5).foregroundStyle(Design.muted)
            }.padding(.horizontal, 21).padding(.top, 17)
            VStack(spacing: 17) {
                SuggestionBar(original: "O'zbekcha", replacement: "Özbekça", app: scenario, preview: true, accept: {}, dismiss: {})
                    .frame(width: 435).shadow(color: .black.opacity(0.12), radius: 12, y: 8)
                HStack(spacing: 13) {
                    Image(systemName: scenario == "Mail" ? "envelope" : scenario == "Browser" ? "globe" : "paperplane").font(.system(size: 18)).foregroundStyle(Design.muted)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(scenario == "Mail" ? "New message" : scenario == "Browser" ? "A text field, anywhere" : "Saved Messages").font(Design.font(10)).foregroundStyle(Design.muted)
                        HStack(spacing: 1) { Text("O'zbekcha").font(Design.font(18)); Rectangle().fill(Design.orange).frame(width: 1.5, height: 21) }
                    }
                    Spacer()
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .medium)).frame(width: 29, height: 29).background(Design.cyan, in: Circle())
                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 38)
                Text("Pause for a moment. Review your sentence. Click Use.").font(Design.font(11)).foregroundStyle(Design.muted)
            }.padding(.top, 23).padding(.bottom, 21)
        }.background(Color(hex: 0xEBF2ED), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct SuggestionBar: View {
    let original: String
    let replacement: String
    let app: String
    var preview = false
    let accept: () -> Void
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 13) {
            YozMark(size: 25)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(original).foregroundStyle(.white.opacity(0.5)).strikethrough()
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Design.cyan)
                    Text(replacement).foregroundStyle(.white)
                }.font(Design.font(17, .medium)).lineLimit(1)
                Text(preview ? "\(app) · preview" : app).font(Design.font(9)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 4)
            Button(action: accept) { Text("Use  ⌥ ↵").font(Design.font(11, .semibold)).padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(.black).background(Design.cyan, in: Capsule()) }.buttonStyle(PointerButtonStyle()).help("Use suggested text · Option Return")
            if !preview {
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).frame(width: 22, height: 30) }.buttonStyle(PointerButtonStyle()).help("Dismiss · Escape")
            }
        }.padding(.horizontal, 17).frame(height: 76).background(Design.ink, in: RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.1)))
    }
}

struct PlaygroundView: View {
    @State private var text = "O'zbekiston — go'zal shaharlar, yangi g'oyalar va cheksiz imkoniyatlar."
    @State private var copied = false
    private var result: String { Transliterator.convert(text) }
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            SectionHeading(eyebrow: "A space to experiment", title: "Meet your new letters.", subtitle: "Type or paste Uzbek Latin text. See every change as you write.")
            HStack { Text("YOUR TEXT").tracking(1.5); Spacer(); Button("Clear") { text = "" }.buttonStyle(PointerButtonStyle()).foregroundStyle(Design.muted) }.font(Design.font(10, .semibold))
            TextEditor(text: $text).font(Design.font(23)).scrollContentBackground(.hidden).padding(16).frame(height: 160).background(.white, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Design.line)).accessibilityLabel("Text to transliterate")
            HStack { Image(systemName: "arrow.down").foregroundStyle(Design.orange); Text("NEW UZBEK ALPHABET").font(Design.font(10, .semibold)).tracking(1.5); Spacer(); Text("\(text.count) characters").font(Design.font(11)).foregroundStyle(Design.muted) }
            Text(result.isEmpty ? "Your new letters will appear here…" : result).font(Design.font(25)).lineSpacing(7).foregroundStyle(result.isEmpty ? Design.muted : Design.ink).textSelection(.enabled).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading).padding(23).background(Design.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
            HStack {
                Text("Latin → new Uzbek Latin").font(Design.font(12)).foregroundStyle(Design.muted)
                Spacer()
                ActionButton(title: copied ? "Copied" : "Copy result", icon: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string); copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }.disabled(text.isEmpty)
            }
            Text("Transliteration changes letters, not meaning. URLs and email addresses are preserved. For separate s + h sounds, keep the apostrophe: Is’hoq.").font(Design.font(12)).foregroundStyle(Design.muted).lineSpacing(5)
        }
    }
}

struct AlphabetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SectionHeading(eyebrow: "28 letters · one apostrophe", title: "Familiar sounds. New forms.", subtitle: "The alphabet from your reference document, pages 2–3.")
            HStack(spacing: 12) {
                ForEach(Array(zip(["o‘", "g‘", "sh", "ch"], ["Ö ö", "Ğ ğ", "Ş ş", "Ç ç"])), id: \.0) { old, new in
                    VStack(alignment: .leading, spacing: 17) {
                        Text(old + "  →").font(Design.font(15)).foregroundStyle(Design.muted)
                        Text(new).font(Design.font(30)).tracking(-1)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(19).background(Design.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 7), spacing: 9) {
                ForEach(Transliterator.alphabet, id: \.self) { letter in
                    VStack(spacing: 8) { Text(letter).font(Design.font(28)); Text(letter.lowercased()).font(Design.font(15)).foregroundStyle(Design.muted) }.frame(maxWidth: .infinity).frame(height: 78).background(["Ö", "Ğ", "Ş", "Ç"].contains(letter) ? Design.cyan.opacity(0.15) : .white, in: RoundedRectangle(cornerRadius: 11))
                }
            }
            Text("“ng” stays as two letters. The apostrophe in ma’no is retained. Yoz accepts straight, curly and modifier apostrophes after o and g, and preserves uppercase letters.").font(Design.font(12)).foregroundStyle(Design.muted).lineSpacing(5)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var apps: [NSRunningApplication] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SectionHeading(eyebrow: "Make it yours", title: "A flow that fits you.", subtitle: "Choose how Yoz suggests and where it stays quiet.")
            DefaultServiceSettingsView(assistant: model.assistant)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Circle().fill(Design.green).frame(width: 6, height: 6); Text("Live detection").font(Design.font(14, .medium)); Spacer(); Text("0.65 s pause").font(Design.font(11)).foregroundStyle(Design.muted) }
                Text(model.liveStatus).font(Design.font(12)).foregroundStyle(Design.muted).textSelection(.enabled)
                Text("\(model.convertedCount) replacements confirmed this session").font(Design.font(10)).foregroundStyle(Design.muted)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Design.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Suggest while I type")
                    Spacer()
                    Toggle("Suggest while I type", isOn: $model.enabled).labelsHidden().toggleStyle(.switch).tint(Design.cyan)
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Apply automatically after a pause")
                        Text("Convert the entire editable field. This also changes sh/ch in other languages.").font(Design.font(11)).foregroundStyle(Design.muted)
                    }
                    Spacer()
                    Toggle("Apply automatically after a pause", isOn: $model.automatic).labelsHidden().toggleStyle(.switch).tint(Design.cyan)
                }
                Divider()
                HStack { Text("Accept suggestion"); Spacer(); Text("⌥ Return").font(.system(size: 12, design: .monospaced)).padding(8).background(Design.paper, in: RoundedRectangle(cornerRadius: 7)) }
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Enable / pause Yoz")
                        Text("Double-press Right Shift, or double-click ö in the menu bar.").font(Design.font(11)).foregroundStyle(Design.muted)
                    }
                    Spacer()
                    Text("⇧ × 2").font(.system(size: 12, design: .monospaced)).foregroundStyle(Design.muted)
                }
                HStack { Text("Dismiss suggestion"); Spacer(); Text("Escape").font(.system(size: 12, design: .monospaced)).foregroundStyle(Design.muted) }
            }.padding(22).background(.white, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 13) {
                HStack { Text("App exclusions").font(Design.font(17, .medium)); Spacer(); Button("Refresh") { refreshApps() }.buttonStyle(PointerButtonStyle()).font(Design.font(12)).foregroundStyle(Design.muted) }
                Text("Turn an app off to stop suggestions there. Password fields and Terminal are skipped automatically.").font(Design.font(12)).foregroundStyle(Design.muted)
                ForEach(apps, id: \.processIdentifier) { app in
                    if let id = app.bundleIdentifier {
                        HStack(spacing: 10) {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                            Text(app.localizedName ?? id).font(Design.font(13))
                            Spacer()
                            Toggle("Enable \(app.localizedName ?? id)", isOn: Binding(get: { !model.excludedApps.contains(id) }, set: { allowed in if allowed { model.excludedApps.remove(id) } else { model.excludedApps.insert(id) } }))
                                .labelsHidden().toggleStyle(.switch).tint(Design.cyan)
                        }.padding(.vertical, 3)
                    }
                }
            }.padding(22).background(.white, in: RoundedRectangle(cornerRadius: 15))
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text("Accessibility").font(Design.font(15, .medium)); Text(model.accessibilityGranted ? (model.shortcutReady ? "Connected · shortcut active" : "Connected · reconnecting shortcut…") : "Allow Yoz in Privacy & Security → Accessibility").font(Design.font(11)).foregroundStyle(Design.muted) }
                Spacer()
                ActionButton(title: "Open settings", icon: "arrow.up.right") { model.openPermissions() }
            }
            TranslationSettingsView(settings: model.assistant.settings)
            if !model.lastNotice.isEmpty { Text(model.lastNotice).font(Design.font(12)).foregroundStyle(Design.muted) }
        }.onAppear { refreshApps() }
    }
    private func refreshApps() {
        apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}
