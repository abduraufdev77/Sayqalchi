import XCTest
@testable import TransliterationCore

final class EditorScopeTests: XCTestCase {
    private final class Node {
        var parent: Node?
        let kind: EditorScope.Kind
        init(_ kind: EditorScope.Kind, parent: Node? = nil) { self.kind = kind; self.parent = parent }
    }
    private let draft = "O'zbekistonda yangi loyiha ustida ishlayapmiz. Bu loyiha shahar va qishloqlarda ishlatiladi, uning chiroyli ko'rinishi va qulay boshqaruv oynasi bor.\n\nDashboard orqali barcha o'zgarishlarni ko'rish mumkin."
    private func editor(_ text: String, selection: NSRange? = nil, parent: Node? = nil) -> Node {
        Node(.editor(.init(text: text, selection: selection ?? NSRange(location: (text as NSString).length, length: 0))), parent: parent)
    }
    private func resolve(_ node: Node) -> (node: Node, content: EditorScope.Content)? {
        EditorScope.resolve(focused: node, parent: { $0.parent }, inspect: { $0.kind })
    }
    func testEitherParagraphResolvesToSameCompleteDraft() throws {
        let page = Node(.boundary)
        let root = editor(draft, parent: page)
        for paragraph in draft.components(separatedBy: "\n\n") {
            var child = editor(paragraph, parent: root)
            // Nested wrappers must not stop discovery after five ancestors.
            for _ in 0..<8 { child = Node(.container, parent: child) }
            let result = try XCTUnwrap(resolve(child))
            XCTAssertTrue(result.node === root)
            XCTAssertEqual(result.content.text, draft)
            let suggestion = try XCTUnwrap(Transliterator.fieldSuggestion(in: result.content.text))
            XCTAssertEqual(suggestion.range, NSRange(location: 0, length: (draft as NSString).length))
            XCTAssertEqual(suggestion.replacement, "Özbekistonda yangi loyiha ustida işlayapmiz. Bu loyiha şahar va qişloqlarda işlatiladi, uning çiroyli körinişi va qulay boşqaruv oynasi bor.\n\nDaşboard orqali barça özgarişlarni köriş mumkin.")
        }
    }
    func testSelectionDoesNotLimitResolvedDraft() throws {
        let range = (draft as NSString).range(of: "Dashboard orqali barcha o'zgarishlarni ko'rish mumkin.")
        let root = editor(draft, selection: range)
        let result = try XCTUnwrap(resolve(root))
        XCTAssertEqual(result.content.text, draft)
        XCTAssertEqual(Transliterator.fieldSuggestion(in: result.content.text)?.range.location, 0)
    }
    func testNeverIncludesReadOnlyHistoryOrUnrelatedTextControl() throws {
        let page = Node(.boundary, parent: editor("History: shahar\n" + draft))
        let root = editor(draft, parent: page)
        XCTAssertEqual(try XCTUnwrap(resolve(root)).content.text, draft)
        let unrelated = editor("Search shahar")
        let child = editor(draft, parent: unrelated)
        XCTAssertTrue(try XCTUnwrap(resolve(child)).node === child)
    }
    func testProtectedAncestorAndInvalidSelectionRejectDraft() {
        XCTAssertNil(resolve(editor(draft, parent: Node(.protected))))
        XCTAssertNil(resolve(editor(draft, selection: NSRange(location: (draft as NSString).length + 1, length: 0))))
    }
    func testUnreadableEditorDoesNotFallBackToOneParagraph() throws {
        let unavailable = Node(.unavailableEditor, parent: Node(.boundary))
        XCTAssertNil(resolve(editor("shahar", parent: unavailable)))
        let full = editor(draft)
        let paragraph = Node(.unavailableEditor, parent: full)
        XCTAssertTrue(try XCTUnwrap(resolve(paragraph)).node === full)
    }
}
