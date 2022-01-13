//
//  PreviewFormatter.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import UIKit

/// Creates a preview of the Drafty object as NSAttributedString .
class PreviewFormatter: AttributedStringFormatter {
    // Default font for previews.
    static let kDefaultFont = UIFont.preferredFont(forTextStyle: .subheadline)
    // Indicates whether the first "MN" node should be stripped.
    // Typically true for forwarded messages.
    public var stripFirstMention: Bool = false

    public init(withDefaultAttributes attrs: [NSAttributedString.Key: Any], isForwardedMessage: Bool) {
        super.init(withDefaultAttributes: attrs)
        stripFirstMention = isForwardedMessage
    }

    required init(withDefaultAttributes attrs: [NSAttributedString.Key : Any]) {
        super.init(withDefaultAttributes: attrs)
    }

    public static func toAttributed(_ content: Drafty, fitIn maxSize: CGSize, withDefaultAttributes attributes: [NSAttributedString.Key: Any]? = nil, isForwarded: Bool = false, upToLength maxLength: Int) -> NSAttributedString {

        var attributes: [NSAttributedString.Key: Any] = attributes ?? [:]
        if attributes[.font] == nil {
            attributes[.font] = PreviewFormatter.kDefaultFont
        }

        if content.isPlain {
            let result: String = content.string.count > maxLength ? content.string.prefix(maxLength) + "…" : content.string
            return NSMutableAttributedString(string: result, attributes: attributes)
        }

        let formatter = PreviewFormatter(withDefaultAttributes: attributes, isForwardedMessage: isForwarded)
        let formatTree = content.format(formatWith: formatter, resultType: FormatNode.self) as! FormatNode
        do {
            return try formatTree.toAttributed(withDefaultAttributes: attributes, fontTraits: nil, fitIn: maxSize, upToLength: maxLength)
        } catch LengthExceededError.runtimeError(let str) {
            let result = NSMutableAttributedString(attributedString: str)
            let elipses = NSAttributedString(string: "…")
            result.append(elipses)
            return result
        } catch {
            return NSAttributedString(string: "")
        }
    }

    override func handleLineBreak() -> FormatNode {
        return FormatNode(" ")
    }

    override func handleLink(content nodes: [FormatNode], using attr: [String: JSONValue]?) -> FormatNode {
        let node = FormatNode(nodes)
        node.style(cstyle: [.foregroundColor: AttributedStringFormatter.Constants.kLinkColor])
        return node
    }

    override func handleMention(content nodes: [FormatNode], using attr: [String : JSONValue]?) -> FormatNode {
        if stripFirstMention {
            stripFirstMention = false
            return FormatNode("➦ ") // FIXME: this should not be here. The conversion should happen earlier.
        }
        return super.handleMention(content: nodes, using: attr)
    }

    func annotatedIcon(iconName: String, annotation: String? = nil, comment: String? = nil) -> FormatNode {
        let icon = NSTextAttachment()
        icon.image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
        let baseFont = PreviewFormatter.kDefaultFont
        icon.bounds = CGRect(origin: CGPoint(x: 0, y: -2), size: CGSize(width: baseFont.lineHeight * 0.8, height: baseFont.lineHeight * 0.8))

        let iconNode = FormatNode()
        iconNode.preformattedAttachment(icon)
        if let annotationStr = annotation, let commentStr = comment {
            let annotationNode = FormatNode(" " + NSLocalizedString(annotationStr, comment: commentStr))
            return FormatNode([iconNode, annotationNode])
        }
        return iconNode
    }

    override func handleImage(using attr: [String: JSONValue]?, fromDraftyEntity key: Int?) -> FormatNode {
        if let mime = attr?["mime"]?.asString(), mime == "application/json" {
            // Skip JSON attachments. They are not meant to be user-visible.
            return FormatNode("")
        }
        return annotatedIcon(iconName: "image-50", annotation: "Picture", comment: "Image preview icon.")
    }

    override func handleAttachment(using attr: [String: JSONValue]?) -> FormatNode {
        return annotatedIcon(iconName: "attach-50", annotation: "Attachment", comment: "Attachment preview icon.")
    }

    override func handleForm(_ nodes: [FormatNode]) -> FormatNode {
        var result = [annotatedIcon(iconName: "form-50", annotation: "Form", comment: "Form preview icon."), FormatNode(": ")]
        result.append(contentsOf: nodes)
        return FormatNode(result)
    }

    override func handleButton(content nodes: [FormatNode], using attr: [String: JSONValue]?) -> FormatNode {
        let attrs: [NSAttributedString.Key: Any] = [.baselineOffset: 0]
        var faceText: NSAttributedString
        if nodes.isEmpty {
            faceText = NSAttributedString(string: "button", attributes: attrs)
        } else {
            faceText = NSAttributedString(string: FormatNode(nodes).toString(), attributes: attrs)
        }
        let att = DraftyButtonAttachment(face: faceText, data: nil, traceBorder: true, widthPadding: 1, heightMultiplier: 1.1, verticalOffset: -2)
        let node = FormatNode()
        node.preformattedAttachment(att)
        return node
    }

    override func handleFormRow(_ nodes: [FormatNode]) -> FormatNode {
        var result = [FormatNode(" "), FormatNode(nodes)]
        result.append(contentsOf: nodes)
        return FormatNode(result)
    }

    override func handleQuote(_ nodes: [FormatNode]) -> FormatNode {
        return FormatNode()
    }

    override func handleUnknown(_ nodes: [FormatNode]) -> FormatNode {
        return annotatedIcon(iconName: "question-mark-50")
    }
}
