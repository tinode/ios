//
//  AttribFormatter.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//
//  Converts Drafty instance into attributed text suitable for display in UITextView

import TinodeSDK
import UIKit

// iOS's support for styled strings is much weaker than Android's and web. Some styles cannot be nested. They have to be constructed and applied all at once at the leaf level.
class AttribFormatter: DraftyFormatter {
    typealias Node = AttribFormatter.TreeNode

    private enum Constants {
        static let kFormLineSpacing: CGFloat = 1.5
        static let kDefaultFont: UIFont = UIFont.preferredFont(forTextStyle: .body)
    }

    typealias CharacterStyle = [NSAttributedString.Key: Any]

    let clicker: UITextViewDelegate?
    let baseFont: UIFont?

    init(baseFont font: UIFont?, clicker: UITextViewDelegate?) {
        self.baseFont = font
        self.clicker = clicker
    }

    // Inline image
    private func handleImage(content: TreeNode, attr: [String : JSONValue]?) {
        guard let attr = attr, let data = attr["val"]?.asString() else { return }

        if let imageData = Data(base64Encoded: data, options: .ignoreUnknownCharacters) {
            var attachment = Attachment()
            attachment.image = UIImage(data: imageData)
            attachment.mime = attr["mime"]?.asString()
            content.attachment(attachment)
        }
    }

    private func handleAttachment(content: TreeNode, attr: [String : JSONValue]?) {
        guard let attr = attr, let data = attr["val"]?.asString() else { return }

        if let bits = Data(base64Encoded: data, options: .ignoreUnknownCharacters) {
            var attachment = Attachment()
            attachment.data = bits
            attachment.mime = attr["mime"]?.asString()
        }
    }

    private func handleButton(content: TreeNode, attr: [String : JSONValue]?) {
        guard let uri = AttribFormatter.buttonDataAsUri(attr) else { return }

        // TODO: ensure button width: if it's the only one in a row, it's fine, if there
        // are multiple buttons per row, add spaces before and after and stretch them by kerning.

        // Create button-like background.
        content.style(cstyle: [
            .buttonBackground: UIColor.white.withAlphaComponent(0.9),
            .baselineOffset: 4, // FIXME: Calculate correct offset from view height and font size
            NSAttributedString.Key.link: NSURL(string: uri) as Any
            ])

        let pstyle = NSMutableParagraphStyle()
        pstyle.alignment = .center
        pstyle.lineHeightMultiple = Constants.kFormLineSpacing
        content.style(pstyle: pstyle)
    }

    // Convert button payload to an URL.
    // NSAttributedString.Key.link wants payload to be NSURL.
    private static func buttonDataAsUri(_ attr: [String : JSONValue]?) -> String? {
        guard let attr = attr, let actionType = attr["act"]?.asString() else { return nil }
        var baseUrl: URLComponents
        if actionType == "url" {
            guard let ref = attr["ref"]?.asString() else { return nil }
            guard let urlc = URLComponents(string: ref) else { return nil }
            baseUrl = urlc
        } else if actionType == "pub" {
            // Custom scheme usr to post back to the server:
            // tinode:default?name=value
            baseUrl = URLComponents()
            baseUrl.scheme = "tinode"
            baseUrl.host = "default"
        } else {
            return nil
        }

        if let name = attr["name"]?.asString() {
            let actionValue = attr["val"]?.asString()
            baseUrl.queryItems?.append(URLQueryItem(name: name, value: actionValue ?? "1"))
        }

        return baseUrl.url?.absoluteString
    }

    // Construct a tree representing formatting styles and content.
    private func apply(tp: String?, attr: [String : JSONValue]?, children: [TreeNode]?, content: String?) -> TreeNode {

        // Create unstyled node
        var span = TreeNode(text: content, nodes: children)
        switch tp {
        case "ST":
            span.style(fontTraits: .traitBold)
        case "EM":
            span.style(fontTraits: .traitItalic)
        case "DL":
            span.style(cstyle: [NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.single.rawValue])
        case "CO":
            span.style(fontTraits: .traitMonoSpace)
        case "BR":
            span = TreeNode(content: "\n")
        case "LN":
            if let url = attr?["url"]?.asString() {
                span.style(cstyle: [NSAttributedString.Key.link: NSURL(string: url) as Any])
            }
        case "MN": break // TODO: add fupport for @mentions
        case "HT": break // TODO: add support for #hashtangs
        case "HD": break // Hidden/ignored text
        case "IM":
            // Inline image
            handleImage(content: span, attr: attr)
        case "EX":
            // Attachment
            handleAttachment(content: span, attr: attr)
        case "BN":
            // Button
            handleButton(content: span, attr: attr)
        case "FM":
            // Form
            if let children = children, !children.isEmpty {
                // Add line breaks between form elements: each row is a paragraph.
                for i in 0..<children.count {
                    span.addNode(node: children[i])
                    span.addNode(content: "\n");
                }
            }
        case "RW":
            // Form element formatting is dependent on element content.
            // No additional handling is needed.
            break
        default:
            break // Unknown formatting, treat as plain text
        }
        return span
    }

    func apply(tp: String?, attr: [String : JSONValue]?, content: [AttribFormatter.TreeNode]) -> AttribFormatter.TreeNode {
        return apply(tp: tp, attr: attr, children: content, content: nil)
    }

    func apply(tp: String?, attr: [String : JSONValue]?, content: String?) -> AttribFormatter.TreeNode {
        return apply(tp: tp, attr: attr, children: nil, content: content)
    }

    /// Convert drafty object into NSAttributedString
    /// - Parameters:
    ///    - content: Drafty object to convert
    ///    - baseFont: base font to derive styles from.
    ///    - clicker: methods to call in response to touch events in formatted text.
    ///    - maxSize: maximum size of attached images
    public static func toAttributed(_ content: Drafty, baseFont font: UIFont?, clicker: UITextViewDelegate?, maxSize: CGSize) -> NSAttributedString {

        if content.isPlain {
            let attributed = NSMutableAttributedString(string: content.string)
            attributed.addAttributes([.font : (font ?? Constants.kDefaultFont)], range: NSRange(location: 0, length: attributed.length))
            return attributed
        }

        let result = content.format(formatter: AttribFormatter(baseFont: font, clicker: clicker))
        let attributed = result.toAttributed(baseFont: font ?? Constants.kDefaultFont, fontTraits: nil, size: maxSize)

        return attributed
    }

    // File or image attachment.
    struct Attachment {
        var data: Data?
        var image: UIImage?
        var mime: String?
    }

    // Class representing Drafty as a tree of nodes with content and styles attached.
    class TreeNode : CustomStringConvertible {

        // A set of font traits to apply at the leaf level
        var cFont: UIFontDescriptor.SymbolicTraits?
        // Character style which can be applied over leaf or subtree
        var cStyle: CharacterStyle?
        // Paragraph-level style to apply to leaf or subtree
        var pStyle: NSMutableParagraphStyle?
        // Attachment. Apple is really bad at designing interfaces.
        var attachment: Attachment?

        // Leaf
        var text: NSMutableAttributedString?
        // Subtree
        var children: [TreeNode]?

        private init() {
            text = nil
            children = nil
        }

        // Create unstyled node
        init(text: String?, nodes: [TreeNode]?) {
            self.text = text == nil ? nil : NSMutableAttributedString(string: text!)
            self.children = nodes
        }

        private init(style: CharacterStyle, nodes: [TreeNode]) {
            self.cStyle = style
            self.text = nil
            self.children = nodes
        }

        convenience init(content: String) {
            self.init(text: content, nodes: nil)
        }

        init(content: [TreeNode]) {
            self.children = content
        }

        init(content: TreeNode) {
            if self.children == nil {
                self.children = []
            }
            self.children!.append(content)
        }

        var description: String {
            return text != nil ? text!.string : children?.description ?? "nil"
        }

        func style(cstyle: CharacterStyle) {
            cStyle = cstyle
        }

        func style(pstyle: NSMutableParagraphStyle) {
            pStyle = pstyle
        }

        func style(fontTraits: UIFontDescriptor.SymbolicTraits) {
            cFont = fontTraits
        }

        func attachment(_ attachment: Attachment) {
            self.attachment = attachment
        }

        func addNode(node: TreeNode?) {
            guard let node = node else { return }

            if children == nil {
                children = []
            }
            children!.append(node)
        }

        func addNode(content: String?) {
            guard let content = content else { return }

            addNode(node: TreeNode(content: content))
        }

        var isEmpty: Bool {
            return (text == nil || text!.length == 0) && (children == nil || children!.isEmpty)
        }

        func toAttributed(baseFont: UIFont, fontTraits parentFontTraits: UIFontDescriptor.SymbolicTraits?, size: CGSize) -> NSMutableAttributedString {
            let attributed = NSMutableAttributedString()

            // First apply font styles to each same-style substring individually.

            // Font traits for this substring and all its children.
            var fontTraits: UIFontDescriptor.SymbolicTraits? = cFont
            if let parentFontTraits = parentFontTraits {
                if fontTraits != nil {
                    fontTraits!.insert(parentFontTraits)
                } else {
                    fontTraits = parentFontTraits
                }
            }

            // First check for attachments.
            if let attachment = self.attachment {
                if let image = attachment.image {
                    let wrapper = NSTextAttachment()
                    wrapper.image = image
                    let (scaledSize, _) = image.sizeUnder(maxWidth: size.width, maxHeight: size.height, clip: false)
                    wrapper.bounds = CGRect(origin: .zero, size: scaledSize)
                    attributed.append(NSAttributedString(attachment: wrapper))
                } else if let bits = attachment.data {
                    attributed.append(NSAttributedString(attachment: NSTextAttachment(data: bits, ofType: attachment.mime)))
                }
            } else if let text = self.text {
                // Uniformly styled substring. Apply uniform font style.
                attributed.append(text)
                let font: UIFont
                if let fontTraits = fontTraits {
                    font = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(fontTraits)!, size: baseFont.pointSize)
                } else {
                    font = baseFont
                }
                attributed.addAttributes([.font : font], range: NSRange(location: 0, length: attributed.length))
            } else if let children = self.children {
                // Pass calculated font styles to children.
                for child in children {
                    attributed.append(child.toAttributed(baseFont: baseFont, fontTraits: fontTraits, size: size))
                }
            }

            // Then apply styles to the entire string.
            if let cstyle = cStyle {
                attributed.addAttributes(cstyle, range: NSRange(location: 0, length: attributed.length))
            } else if let pstyle = pStyle {
                attributed.addAttributes([.paragraphStyle: pstyle], range: NSRange(location: 0, length: attributed.length))
            }

            return attributed
        }
    }
}
