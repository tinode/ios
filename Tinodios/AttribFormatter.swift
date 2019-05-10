//
//  AttribFormatter.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//
//  Converts Drafty instance into attributed text suitable for display in UITextView

import Foundation
import TinodeSDK
import UIKit

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
        guard let attr = attr, let data = attr["val"] else { return }
        let image = NSTextAttachment(data: data.asData(), ofType: attr["mime"]?.asString())
        // FIXME: probably should clear the anchor text.
        content.style(cstyle: [NSAttributedString.Key.attachment: image])
    }

    private func handleAttachment(content: TreeNode, attr: [String : JSONValue]?) {
        guard let attr = attr, let data = attr["val"] else { return }
        let file = NSTextAttachment(data: data.asData(), ofType: attr["mime"]?.asString())
        // FIXME: probably should clear the anchor text.
        content.style(cstyle: [NSAttributedString.Key.attachment: file])
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

    private func apply(tp: String?, attr: [String : JSONValue]?, children: [TreeNode]?, content: String?) -> TreeNode {

        // Create unstyled node
        var span = TreeNode(text: content, nodes: children)
        switch tp {
        case "ST":
            span.style(cstyle: [NSAttributedString.Key.font: font(.traitBold)])
        case "EM":
            span.style(cstyle: [NSAttributedString.Key.font: font(.traitItalic)])
        case "DL":
            span.style(cstyle: [NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.single.rawValue])
        case "CO":
            span.style(cstyle: [NSAttributedString.Key.font: font(.traitMonoSpace)])
        case "BR":
            span = TreeNode(content: "\n")
        case "LN":
            if let url = attr?["url"]?.asString() {
                span.style(cstyle: [NSAttributedString.Key.link: NSURL(string: url) as Any])
            }
        case "MN": break // TODO: add fupport for @mentions
        case "HT": break // TODO: add support for #hashtangs
        case "HD": break // Hidden text
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

    public static func toAttributed(baseFont font: UIFont?, content: Drafty?, clicker: UITextViewDelegate?) -> NSAttributedString {
        guard let content = content else {
            return NSAttributedString(string: "")
        }
        if content.isPlain {
            return NSAttributedString(string: content.string)
        }

        let result = content.format(formatter: AttribFormatter(baseFont: font, clicker: clicker))
        let attributed = result.toAttributed()

        return attributed
    }

    // Take font from the container and create the same size and family font with a given trait.
    private func font(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let font = baseFont ?? Constants.kDefaultFont
        return UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(trait)!, size: font.pointSize)
    }

    // Structure representing Drafty as a tree of formatting nodes.
    class TreeNode : CustomStringConvertible {

        var cStyle: CharacterStyle?
        var pStyle: NSMutableParagraphStyle?
        var text: NSMutableAttributedString?
        var children: [TreeNode]?

        private init() {
            cStyle = nil
            pStyle = nil
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

        func toAttributed() -> NSMutableAttributedString {
            let attributed = NSMutableAttributedString()
            if let text = self.text {
                attributed.append(text)
            } else if let children = self.children {
                for child in children {
                    attributed.append(child.toAttributed())
                }
            }

            if let cstyle = cStyle {
                attributed.addAttributes(cstyle, range: NSRange(location: 0, length: attributed.length))
            } else if let pstyle = pStyle {
                attributed.addAttributes([NSAttributedString.Key.paragraphStyle: pstyle], range: NSRange(location: 0, length: attributed.length))
            }

            return attributed
        }
    }
}
