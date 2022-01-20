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
class PreviewFormatter: AbstractFormatter {
    static let kDefaultFont = UIFont.preferredFont(forTextStyle: .subheadline)

    init(defaultAttributes attrs: [NSAttributedString.Key : Any]) {
        super.init(defaultAttributes: attrs, defaultFont: PreviewFormatter.kDefaultFont)
    }

    override func handleLineBreak() -> FormatNode {
        return FormatNode(" ")
    }

    override func handleMention(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        return FormatNode(nodes)
    }

    override func handleLink(content nodes: [FormatNode], using attr: [String: JSONValue]?) -> FormatNode {
        let node = FormatNode(nodes)
        node.style(cstyle: [.foregroundColor: FormatNode.Constants.kLinkColor])
        return node
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

    override func handleImage(using attr: [String: JSONValue]?) -> FormatNode {
        return annotatedIcon(iconName: "image-50", annotation: NSLocalizedString("Picture", comment: "Label shown next to an inline image"), comment: "Image preview icon.")
    }

    override func handleAttachment(using attr: [String: JSONValue]?) -> FormatNode {
        guard let attr = attr else {
            return FormatNode()
        }

        if let mime = attr["mime"]?.asString(), mime == "application/json" {
            // Skip JSON attachments. They are not meant to be user-visible.
            return FormatNode()
        }

        return annotatedIcon(iconName: "paperclip", annotation: NSLocalizedString("Attachment", comment: "Label shown next to an attachment"), comment: "Attachment preview icon.")
    }

    override func handleForm(_ nodes: [FormatNode]) -> FormatNode {
        var result = [annotatedIcon(iconName: "form-50", annotation: NSLocalizedString("Form", comment: "Label shown next to a form in preview"), comment: "Form preview icon."), FormatNode(": ")]
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
        let att = ButtonAttachment(face: faceText, data: nil, traceBorder: true, widthPadding: 1, heightMultiplier: 1.2, verticalOffset: -3)
        let node = FormatNode()
        node.preformattedAttachment(att)
        return node
    }

    override func handleFormRow(_ nodes: [FormatNode]) -> FormatNode {
        return FormatNode([FormatNode(" "), FormatNode(nodes)])
    }

    override func handleQuote(_ nodes: [FormatNode]) -> FormatNode {
        // Quote within preview is blank.
        return FormatNode()
    }

    override func handleUnknown(_ nodes: [FormatNode]) -> FormatNode {
        return annotatedIcon(iconName: "puzzlepiece")
    }
}
