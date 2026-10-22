import AppKit
import SwiftUI
import AssistantCore
import TransliterationCore

struct AssistantNotchView: View {
    @ObservedObject var assistant: AssistantModel
    @Namespace private var tabSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                ForEach(WritingTool.allCases) { tool in
                    Button { withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86)) { assistant.choose(tool) } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tool.icon)
                            if assistant.tool == tool { Text(tool.rawValue) }
                        }.font(Design.font(11, .semibold)).foregroundStyle(assistant.tool == tool ? .white : .white.opacity(0.48))
                            .padding(.horizontal, 13).frame(height: 30)
                            .background {
                                if assistant.tool == tool {
                                    Capsule().fill(.white.opacity(0.16))
                                        .overlay(Capsule().strokeBorder(.white.opacity(0.13), lineWidth: 0.7))
                                        .matchedGeometryEffect(id: "tool-pill", in: tabSelection)
                                }
                            }
                    }.buttonStyle(PointerButtonStyle()).help(tool.rawValue).accessibilityLabel(tool.rawValue)
                }
                Spacer(minLength: 0)
                Button { assistant.close() } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 26, height: 30) }
                    .buttonStyle(PointerButtonStyle()).foregroundStyle(.white.opacity(0.55)).accessibilityLabel("Close assistant")
            }.padding(3).background(.white.opacity(0.065), in: Capsule())
            HStack(spacing: 6) {
                Circle().fill(Design.green).frame(width: 4, height: 4)
                Text(assistant.sourceName).lineLimit(1)
                Text("· " + assistant.scope).foregroundStyle(.white.opacity(0.3))
                Spacer()
                Button { assistant.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(PointerButtonStyle()).help("Refresh current draft")
                Button { assistant.edit() } label: { Image(systemName: "square.and.pencil") }.buttonStyle(PointerButtonStyle()).help("Enter or paste text")
            }.font(Design.font(9, .medium)).foregroundStyle(.white.opacity(0.5))
            if assistant.tool == .translate { TranslationLanguagePicker(assistant: assistant) }
            if assistant.editing {
                TextEditor(text: $assistant.input).font(Design.font(13)).scrollContentBackground(.hidden)
                    .padding(8).frame(height: 86).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel(assistant.tool == .dictionary ? "Word or phrase to look up" : "Assistant input")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if assistant.tool == .dictionary { dictionaryBody }
                    else if assistant.tool == .document { documentBody }
                    else if !assistant.output.isEmpty { resultText }
                    else { inputPreview }
                    if !assistant.error.isEmpty {
                        Text(assistant.error).font(Design.font(11)).foregroundStyle(Design.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .id(assistant.tool)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 4)))
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 12) {
                Button { assistant.run() } label: {
                    HStack(spacing: 6) {
                        if assistant.busy { ProgressView().controlSize(.mini).scaleEffect(0.7) }
                        Text(actionTitle)
                    }.font(Design.font(11, .semibold)).foregroundStyle(.black).padding(.horizontal, 14).frame(height: 29)
                        .background(Design.cyan, in: Capsule())
                }.buttonStyle(PointerButtonStyle()).disabled(assistant.busy)
                if assistant.busy {
                    Button("Cancel") { assistant.resetResult() }.buttonStyle(PointerButtonStyle()).font(Design.font(10)).foregroundStyle(.white.opacity(0.6))
                } else if !assistant.output.isEmpty || assistant.entry != nil {
                    Button { assistant.copy() } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }.buttonStyle(NotchActionStyle()).help("Copy result")
                    Button {
                        if assistant.details { assistant.editing = false }
                        assistant.details.toggle(); assistant.resize?()
                    } label: {
                        Label(assistant.details ? "Less" : "More", systemImage: assistant.details ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }.buttonStyle(NotchActionStyle())
                }
                Spacer(minLength: 0)
                if !assistant.appliedNotice.isEmpty { Text(assistant.appliedNotice).font(Design.font(9)).foregroundStyle(Design.green) }
                if assistant.canApply {
                    Button { assistant.apply() } label: {
                        HStack(spacing: 6) { Text("⌥"); Text("↵") }.font(.system(size: 19, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Design.cyan).padding(.horizontal, 11).frame(height: 30)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Design.cyan.opacity(0.35), lineWidth: 0.7))
                    }.buttonStyle(PointerButtonStyle()).help("Replace entire captured draft · Option Return").accessibilityLabel("Apply assistant result")
                }
            }.padding(.bottom, 12)
        }.foregroundStyle(.white)
    }
    private var actionTitle: String {
        if assistant.busy { return "Working…" }
        switch assistant.tool { case .format: return "Format"; case .translate: return "Translate"; case .dictionary: return "Find meaning"; case .document: return "Clean spacing" }
    }
    private var inputPreview: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(assistant.tool == .format ? "A little shift in your letters." : "A bridge between languages.")
                .font(Design.font(19, .medium)).tracking(-0.4)
            Text(assistant.input.isEmpty ? "Focus a draft and hover here, or use the pencil to paste text." : String(assistant.input.prefix(assistant.details ? 16000 : 600)))
                .font(Design.font(12)).lineSpacing(3).foregroundStyle(.white.opacity(0.55))
        }
    }
    @ViewBuilder private var resultText: some View {
        let text = assistant.tool == .format ? Transliterator.runs(in: assistant.input).reduce(Text("")) {
            $0 + Text($1.text).foregroundColor($1.changed ? Design.orange : .white)
        } : Text(assistant.output).foregroundColor(Design.orange)
        text.font(Design.font(assistant.details ? 14 : 13)).lineSpacing(3).textSelection(.enabled)
        if !assistant.details && assistant.output.count > 800 {
            Text("Scroll to review the whole result, or open More.").font(Design.font(9)).foregroundStyle(.white.opacity(0.4))
        }
    }
    @ViewBuilder private var dictionaryBody: some View {
        if let entry = assistant.entry {
            HStack {
                Text(entry.word).font(Design.font(22, .medium)).foregroundStyle(Design.orange)
                Spacer()
                Text("\(entry.meanings.count) meanings").font(Design.font(9)).foregroundStyle(.white.opacity(0.4))
            }
            ForEach(Array((assistant.details ? entry.meanings : entry.preview).enumerated()), id: \.offset) { index, meaning in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(index + 1). " + meaning.definition).font(Design.font(13, .medium)).fixedSize(horizontal: false, vertical: true)
                    // One example per meaning in both sizes keeps the entry easy to scan.
                    if let example = meaning.examples.first {
                        Text(example).font(Design.font(11)).foregroundStyle(.white.opacity(0.48)).lineSpacing(3)
                            .lineLimit(assistant.details ? nil : 3)
                    }
                }.padding(.bottom, 3)
            }
            Link("Izoh.uz ↗", destination: entry.source).pointerCursor().font(Design.font(10, .medium)).foregroundStyle(Design.cyan)
        } else {
            Text("Izohchi").font(Design.font(21, .medium))
            Text(assistant.input.isEmpty ? "Select a word or short phrase in your draft, then hover here. You can also enter a query with the pencil." : String(assistant.input.prefix(140)))
                .font(Design.font(12)).foregroundStyle(.white.opacity(0.6))
            Text("Free lookup · Izoh.uz · only the query is sent").font(Design.font(9)).foregroundStyle(.white.opacity(0.35))
            if let url = try? DictionaryService.sourceURL(assistant.input) {
                HStack(spacing: 14) {
                    Link("Open Izoh.uz ↗", destination: url)
                    Link("Savodxon ↗", destination: URL(string: "https://savodxon.uz/izoh")!.appending(queryItems: [URLQueryItem(name: assistant.input, value: nil)]))
                }.font(Design.font(10)).foregroundStyle(Design.cyan)
            }
        }
    }
    private var documentBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                stat("\(assistant.statistics.words)", "words")
                stat("\(assistant.statistics.characters)", "characters")
                stat("\(assistant.statistics.paragraphs)", "text lines")
                stat("~\(assistant.statistics.readingMinutes)m", "read time")
            }
            if !assistant.output.isEmpty { resultText }
            else {
                Text("Clean repeated spaces and trailing whitespace while preserving paragraph breaks and indentation.")
                    .font(Design.font(12)).foregroundStyle(.white.opacity(0.55)).lineSpacing(3)
            }
            Text("On your Mac · preview before replacing").font(Design.font(9)).foregroundStyle(.white.opacity(0.35))
        }
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Design.font(20, .medium)).foregroundStyle(Design.green)
            Text(label).font(Design.font(9)).foregroundStyle(.white.opacity(0.4))
        }
    }
}

struct TranslationSettingsView: View {
    @ObservedObject var settings: ServiceSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Translation service", systemImage: "globe").font(Design.font(17, .medium))
            Text("Translation sends the text you choose to this service. Formatting and document tools run locally. Izohchi sends only your lookup query to Izoh.uz.")
                .font(Design.font(12)).foregroundStyle(Design.muted).lineSpacing(4)
            TextField("HTTPS service URL", text: $settings.url).textFieldStyle(.roundedBorder).accessibilityLabel("Translation service URL")
            Toggle("Allow unencrypted HTTP for this service", isOn: $settings.allowInsecureHTTP).font(Design.font(12))
            if settings.allowInsecureHTTP {
                Text("HTTP exposes the API key and translated text to the network. Use a trusted development connection only; HTTPS is recommended.")
                    .font(Design.font(11)).foregroundStyle(Design.orange)
            }
            SecureField("API key", text: $settings.token).textFieldStyle(.roundedBorder).accessibilityLabel("Translation API key")
            HStack {
                Button("Save to Keychain") { settings.save() }
                Spacer()
                Button("Import .env…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.showsHiddenFiles = true
                    if panel.runModal() == .OK, let url = panel.url { settings.importEnvironment(url) }
                }
            }
            Text(settings.notice.isEmpty ? "Your API key is never included in the app bundle or repository." : settings.notice)
                .font(Design.font(11)).foregroundStyle(Design.muted)
        }.padding(22).background(.white, in: RoundedRectangle(cornerRadius: 15))
    }
}

struct NotchActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Design.font(10, .semibold)).labelStyle(.titleAndIcon)
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.6 : 0.85))
            .padding(.horizontal, 10).frame(height: 29)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.7))
            .contentShape(Capsule()).pointerCursor()
    }
}

private enum TranslationLanguage: String, CaseIterable, Identifiable {
    case uzbek = "uz-Latn", english = "en", russian = "ru", cyrillic = "uz-Cyrl"
    var id: String { rawValue }
    var name: String {
        switch self { case .uzbek: return "O‘zbek"; case .english: return "English"; case .russian: return "Русский"; case .cyrillic: return "Ўзбек" }
    }
    var subtitle: String {
        switch self { case .uzbek: return "Latin"; case .english: return "English"; case .russian: return "Russian"; case .cyrillic: return "Cyrillic" }
    }
    var badge: String {
        switch self { case .uzbek: return "UZ"; case .english: return "EN"; case .russian: return "RU"; case .cyrillic: return "ЎЗ" }
    }
}

private struct TranslationLanguagePicker: View {
    @ObservedObject var assistant: AssistantModel
    @State private var sourceOpen = false
    @State private var targetOpen = false
    private var source: TranslationLanguage { TranslationLanguage(rawValue: assistant.direction.languages.0)! }
    private var target: TranslationLanguage { TranslationLanguage(rawValue: assistant.direction.languages.1)! }
    private var targets: [TranslationLanguage] {
        TranslationLanguage.allCases.filter { language in
            TranslationDirection.allCases.contains { $0.languages == (source.rawValue, language.rawValue) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Button { sourceOpen.toggle() } label: { badge(source, role: "FROM") }
                    .buttonStyle(PointerButtonStyle()).accessibilityLabel("Source language: \(source.name)")
                    .popover(isPresented: $sourceOpen, arrowEdge: .bottom) {
                        options(TranslationLanguage.allCases, selected: source) { language in
                            let direction = TranslationDirection.allCases.first { $0.languages == (language.rawValue, target.rawValue) }
                                ?? TranslationDirection.allCases.first { $0.languages.0 == language.rawValue }
                            if let direction { assistant.direction = direction }
                            sourceOpen = false
                        }
                    }
                Button {
                    if let reverse = TranslationDirection.allCases.first(where: { $0.languages == (target.rawValue, source.rawValue) }) {
                        assistant.direction = reverse
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5)).frame(width: 28, height: 36)
                }.buttonStyle(PointerButtonStyle()).help("Swap languages").accessibilityLabel("Swap languages")
                Button { targetOpen.toggle() } label: { badge(target, role: "TO") }
                    .buttonStyle(PointerButtonStyle()).accessibilityLabel("Target language: \(target.name)")
                    .popover(isPresented: $targetOpen, arrowEdge: .bottom) {
                        options(targets, selected: target) { language in
                            if let direction = TranslationDirection.allCases.first(where: { $0.languages == (source.rawValue, language.rawValue) }) {
                                assistant.direction = direction
                            }
                            targetOpen = false
                        }
                    }
            }
            Text("Sends this text to your configured service only when you click Translate.")
                .font(Design.font(9)).foregroundStyle(.white.opacity(0.42))
        }
    }
    private func badge(_ language: TranslationLanguage, role: String) -> some View {
        HStack(spacing: 9) {
            Text(language.badge).font(Design.font(10, .semibold)).foregroundStyle(Design.cyan)
                .frame(width: 29, height: 29).background(Design.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(role).font(Design.font(7, .semibold)).tracking(1).foregroundStyle(.white.opacity(0.35))
                Text(language.name).font(Design.font(12, .medium)).lineLimit(1)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
        }.padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 46)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1), lineWidth: 0.7))
    }
    private func options(_ languages: [TranslationLanguage], selected: TranslationLanguage, choose: @escaping (TranslationLanguage) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("CHOOSE LANGUAGE").font(Design.font(8, .semibold)).tracking(1).foregroundStyle(.white.opacity(0.35)).padding(8)
            ForEach(languages) { language in
                Button { choose(language) } label: {
                    HStack(spacing: 10) {
                        Text(language.badge).font(Design.font(10, .semibold)).foregroundStyle(Design.cyan).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.name).font(Design.font(12, .medium))
                            Text(language.subtitle).font(Design.font(9)).foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        if language == selected { Circle().fill(Design.cyan).frame(width: 5, height: 5) }
                    }.padding(9).background(language == selected ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(PointerButtonStyle())
            }
        }.padding(8).frame(width: 202).preferredColorScheme(.dark)
    }
}
