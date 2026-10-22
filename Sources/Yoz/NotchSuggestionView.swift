import AppKit
import SwiftUI
import TransliterationCore

/// A screen-edge silhouette: small concave shoulders at the top and rounded
/// lower corners. Its black top is flush with the physical camera housing.
struct NotchSilhouette: Shape {
    func path(in r: CGRect) -> Path {
        let shoulder = min(12, r.height / 3), radius = min(25, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: r.width, y: 0))
        p.addQuadCurve(to: CGPoint(x: r.width - shoulder, y: shoulder), control: CGPoint(x: r.width - shoulder, y: 0))
        p.addLine(to: CGPoint(x: r.width - shoulder, y: r.height - radius))
        p.addQuadCurve(to: CGPoint(x: r.width - shoulder - radius, y: r.height), control: CGPoint(x: r.width - shoulder, y: r.height))
        p.addLine(to: CGPoint(x: shoulder + radius, y: r.height))
        p.addQuadCurve(to: CGPoint(x: shoulder, y: r.height - radius), control: CGPoint(x: shoulder, y: r.height))
        p.addLine(to: CGPoint(x: shoulder, y: shoulder))
        p.addQuadCurve(to: .zero, control: CGPoint(x: shoulder, y: 0))
        p.closeSubpath()
        return p
    }
}

final class NotchPresentation: ObservableObject {
    @Published var width: CGFloat = 317
    @Published var height: CGFloat = 33
    @Published var contentWidth: CGFloat = 269
    @Published var contentHeight: CGFloat = 148
    @Published var contentOffsetX: CGFloat = 0
    @Published var reducedMotion = false
    @Published var safeTop: CGFloat = 32
    @Published var notchWidth: CGFloat = 185
    @Published var typing = false
    @Published var result = false
    @Published var settling = false
    @Published var preview = false
    @Published var app = ""
    @Published var replacement = ""
    @Published var highlighted = Text("")
    var assistant: AssistantModel?
    var hover: (Bool) -> Void = { _ in }
    var accept: () -> Void = {}
    var dismiss: () -> Void = {}
    var open: () -> Void = {}
    var toggle: () -> Void = {}
}

/// Explicitly interpolate the silhouette, rather than scaling the entire
/// hosting tree. The band is a sibling and never inherits this animation.
struct NotchMorph: AnimatableModifier {
    var width: CGFloat
    var height: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set { width = newValue.first; height = newValue.second }
    }
    func body(content: Content) -> some View {
        content.frame(width: width, height: height, alignment: .top)
            .background(.black, in: NotchSilhouette())
            .clipShape(NotchSilhouette())
    }
}

struct NotchRootView: View {
    @ObservedObject var state: NotchPresentation
    var body: some View {
        ZStack(alignment: .top) {
            if let assistant = state.assistant, assistant.visible {
                Group {
                    if assistant.compactResult { AssistantCompactResultView(assistant: assistant) }
                    else { AssistantNotchView(assistant: assistant) }
                }
                    .frame(width: state.contentWidth, height: state.contentHeight)
                    .padding(.top, state.safeTop + 7)
                    .transition(.opacity)
            } else if state.result {
                NotchSuggestionView(state: state)
                    .frame(width: state.contentWidth, height: state.contentHeight)
                    .transaction { $0.animation = nil }
                    .padding(.top, state.safeTop)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: state.reducedMotion ? 1 : 0.985, anchor: .top))
                            .animation(.easeOut(duration: state.reducedMotion ? 0.12 : 0.22).delay(state.reducedMotion ? 0 : 0.075)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))))
            } else { Color.clear }
        }
        .modifier(NotchMorph(width: state.width, height: state.height))
        .offset(x: state.contentOffsetX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The persistent band lives outside the morphing/clipping layer. Its
        // coordinate updates commit immediately when the native canvas changes.
        .overlay(alignment: .top) {
            NotchActivityView(isTyping: state.typing || state.settling, notchWidth: state.notchWidth, resultReady: state.result || state.assistant?.resultPresented == true)
                .frame(width: NotchLayout(notchWidth: state.notchWidth).bandWidth, height: state.safeTop)
                .offset(x: state.contentOffsetX)
                .transaction { $0.animation = nil }
        }
        .onHover(perform: state.hover)
        .contextMenu {
            Button("Open Sayqalchi", action: state.open)
            Button("Pause Sayqalchi", action: state.toggle)
        }
        .preferredColorScheme(.dark)
    }
}

struct NotchSuggestionView: View {
    @ObservedObject var state: NotchPresentation
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(state.preview ? "PREVIEW" : state.app.uppercased())
                    .font(Design.font(8, .semibold)).tracking(1).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                Spacer()
                Button(action: state.dismiss) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6)).frame(width: 24, height: 22)
                }.buttonStyle(PointerButtonStyle()).accessibilityLabel("Dismiss suggestion").help("Dismiss · Escape")
            }.padding(.bottom, 7)
            ScrollView(.vertical) {
                state.highlighted.font(Design.font(14, .medium)).lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityLabel("Suggested text: \(state.replacement)")
            HStack {
                Text("Entire draft").font(Design.font(9)).foregroundStyle(.white.opacity(0.42))
                Spacer()
                if state.preview { keycaps }
                else {
                    Button(action: state.accept) { keycaps }.buttonStyle(PointerButtonStyle())
                        .accessibilityLabel("Use suggested text").help("Apply entire draft · Option Return")
                }
            }.padding(.top, 8).padding(.bottom, 10)
        }
    }
    private var keycaps: some View {
        HStack(spacing: 7) {
            Text("⌥")
            Text("↵")
        }
        .font(.system(size: 20, weight: .semibold, design: .monospaced))
        .foregroundStyle(Design.cyan).padding(.horizontal, 12).frame(height: 30)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Design.cyan.opacity(0.35), lineWidth: 0.7))
    }
}

/// Clicking Use must work on the first click without making Yoz the active app.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        if #available(macOS 13.3, *) { safeAreaRegions = [] }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
}

/// Compact ears sit beside the physical camera cutout. Animation is limited to
/// this tiny view and pauses completely when idle or Reduce Motion is enabled.
struct NotchActivityView: View {
    let isTyping: Bool
    let notchWidth: CGFloat
    var resultReady = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var body: some View {
        let layout = NotchLayout(notchWidth: notchWidth)
        HStack(spacing: 0) {
            Text("ö").font(Design.font(23, .medium)).foregroundStyle(Design.brandGradient)
                .frame(width: NotchLayout.logoSize.width, height: NotchLayout.logoSize.height)
                .frame(width: layout.earContentWidth, alignment: .leading)
            Color.clear.frame(width: layout.notchWidth)
            TimelineView(.animation(minimumInterval: 1.0 / 18, paused: !isTyping || reduceMotion || lowPower)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    for i in 0..<7 {
                        let wave = isTyping ? (0.5 + 0.5 * sin((reduceMotion ? 0 : t * 7) + Double(i) * 0.8)) : (resultReady ? 0.35 + Double(i % 3) * 0.15 : 0.12)
                        let height = 3 + 12 * wave
                        let rect = CGRect(x: Double(i) * 5, y: (size.height - height) / 2, width: 3, height: height)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(i < 4 ? Design.cyan : Design.green))
                    }
                }
            }.frame(width: NotchLayout.waveformSize.width, height: NotchLayout.waveformSize.height)
                .opacity(isTyping || resultReady ? 1 : 0.5)
                .frame(width: layout.earContentWidth, alignment: .trailing)
        }.padding(.horizontal, NotchLayout.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black, in: NotchSilhouette())
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(resultReady ? "Sayqalchi result ready" : isTyping ? "Sayqalchi is following your typing" : "Sayqalchi enabled")
            .help(isTyping ? "Typing… pause to review all converted text" : "Sayqalchi is enabled")
    }
}
