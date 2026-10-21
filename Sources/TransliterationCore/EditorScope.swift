import Foundation

/// Resolves a focused paragraph to its enclosing editable draft, without
/// crossing into a document, window, or another independent text control.
public enum EditorScope {
    public struct Content {
        public let text: String
        public let selection: NSRange
        public init(text: String, selection: NSRange) {
            self.text = text; self.selection = selection
        }
    }
    public enum Kind {
        case container, editor(Content), unavailableEditor, boundary, protected
    }
    public static func resolve<Node>(focused: Node, parent: (Node) -> Node?,
                                     inspect: (Node) -> Kind) -> (node: Node, content: Content)? {
        var node: Node? = focused
        var result: (node: Node, content: Content)?
        for _ in 0..<32 {
            guard let current = node else { break }
            switch inspect(current) {
            case .protected: return nil
            case .boundary: return result
            case .container: break
            case .unavailableEditor: result = nil
            case .editor(let content):
                let length = (content.text as NSString).length
                guard content.selection.location >= 0, content.selection.length >= 0,
                      content.selection.location <= length,
                      content.selection.length <= length - content.selection.location else { return nil }
                if let previous = result, !content.text.contains(previous.content.text) { return result }
                result = (current, content)
            }
            node = parent(current)
        }
        return result
    }
}
