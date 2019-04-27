//
//  AttribFormatter.swift
//  Tinodios
//
//  Created by Gene Sokolov on 27/04/2019.
//  Copyright © 2019 Tinode. All rights reserved.
//
//  Converts Drafty instance into attributed text suitable for display in UITextView

import Foundation
import TinodeSDK
import UIKit

class AttribFormatter: DraftyFormatter {
    typealias Node = AttribFormatter.TreeNode

    private static let kFormLineSpacing: CFloat = 1.5

    typealias CharacterStyle = [NSAttributedString.Key: Any]
    //let container: UILabel
    //let viewportWidth: CGFloat
    let clicker: UITextViewDelegate?

    init(container: UILabel?, clicker: UITextViewDelegate?) {
        //self.container = container
        //self.viewportWidth = container.frame.width
        self.clicker = clicker
    }

    private func handleImage(ctx: Void, content: TreeNode, attr: [String : JSONValue]?) {
    }

    private func handleAttachment(ctx: Void, content: TreeNode, attr: [String : JSONValue]?) {
    }

    private func handleButton(content: TreeNode, attr: [String : JSONValue]?) {
        // Create border around text.
        /*
        content.style(cstyle: [
            .strokeWidth: -3.0,
            .strokeColor: UIColor.yellow,
            .foregroundColor: UIColor.red,
            NSAttributedString.Key.link: NSURL(string: url) as Any
            ])
        */
    }

    // Convert button payload to an URL.
    // NSAttributedString.Key.link wants payload to be NSURL.
    private static func buttonDataAsUrl(attr: [String : JSONValue]) -> URL? {
        guard let actionType = attr["act"]?.asString() else { return nil }
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

        return baseUrl.url
    }

    internal func apply(tp: String?, attr: [String : JSONValue]?, children: [TreeNode]?, content: String?) -> TreeNode {

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
        case "MN": break
        case "HT": break
        case "HD": break // Hidden text
        case "IM":
            // Additional processing for images
            handleImage(ctx: Void(), content: span, attr: attr)
        case "EX":
            // Attachments
            handleAttachment(ctx: Void(), content: span, attr: attr)
        case "BN":
            // Button
            handleButton(content: span, attr: attr)
        case "FM":
            // Form
            if let children = children, !children.isEmpty {
                // Add line breaks between form elements.
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

    public static func toAttributed(container: UILabel?, content: Drafty?, clicker: UITextViewDelegate?) -> NSAttributedString {
        guard let content = content else {
            return NSAttributedString(string: "")
        }
        if content.isPlain {
            return NSAttributedString(string: content.string)
        }

        let result = content.format(formatter: AttribFormatter(container: container, clicker: clicker))
        return result.toAttributed()
    }

    // Take the default font from container and create the same size and family font with a given trait.
    private func font(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let normalFont = UIFont.preferredFont(forTextStyle: .body)
        // let normalFont = container.font!
        return UIFont(descriptor: normalFont.fontDescriptor.withSymbolicTraits(trait)!, size: normalFont.pointSize)
    }

    // Structure representing Drafty as a tree of formatting nodes.
    internal class TreeNode {
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

        func toAttributed() -> NSAttributedString {
            let attributed = NSMutableAttributedString(string: "")
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
                //attributed.addAttributes(pstyle, range: NSRange(location: 0, length: attributed.length))
            }

            return attributed
        }
    }
}
