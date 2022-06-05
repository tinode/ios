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

    static func annotatedIcon(iconName: String, localizedAnnotation: String? = nil) -> FormatNode {
        let icon = NSTextAttachment()
        icon.image = (UIImage(systemName: iconName) ?? UIImage(named: iconName))?.withRenderingMode(.alwaysTemplate)
        let baseFont = PreviewFormatter.kDefaultFont
        icon.bounds = CGRect(origin: CGPoint(x: 0, y: -2), size: CGSize(width: baseFont.lineHeight * 0.8, height: baseFont.lineHeight * 0.8))

        let iconNode = FormatNode()
        iconNode.preformattedAttachment(icon)
        if let annotationStr = localizedAnnotation {
            return FormatNode([iconNode, FormatNode(" " + annotationStr)])
        }
        return iconNode
    }

    override func handleAudio(using attr: [String: JSONValue]?, draftyKey _: Int?) -> FormatNode {
        var annotation: String
        if let attr = attr, let duration = attr["duration"]?.asInt() {
            annotation = PreviewFormatter.millisToTime(millis: duration, fixedMin: true)
        } else {
            annotation = "-:--"
        }
        return PreviewFormatter.annotatedIcon(iconName: "mic", localizedAnnotation: annotation)
    }

    override func handleImage(using attr: [String: JSONValue]?, draftyKey _: Int?) -> FormatNode {
        return PreviewFormatter.annotatedIcon(iconName: "image-50", localizedAnnotation: NSLocalizedString("Picture", comment: "Label shown next to an inline image"))
    }

    override func handleAttachment(using attr: [String: JSONValue]?, draftyKey _: Int?) -> FormatNode {
        guard let attr = attr else {
            return FormatNode()
        }

        if let mime = attr["mime"]?.asString(), mime == "application/json" {
            // Skip JSON attachments. They are not meant to be user-visible.
            return FormatNode()
        }

        return PreviewFormatter.annotatedIcon(iconName: "paperclip", localizedAnnotation: NSLocalizedString("Attachment", comment: "Label shown next to an attachment"))
    }

    override func handleForm(_ nodes: [FormatNode]) -> FormatNode {
        var result = [PreviewFormatter.annotatedIcon(iconName: "form-50", localizedAnnotation: NSLocalizedString("Form", comment: "Label shown next to a form in preview")), FormatNode(": ")]
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

    override func handleUnknown(content _: [FormatNode], using _: [String: JSONValue]?, draftyKey _: Int?) -> FormatNode {
        return PreviewFormatter.annotatedIcon(iconName: "puzzlepiece.extension", localizedAnnotation: NSLocalizedString("Unsupported", comment: "Label shown next to an unsupported Drafty format element"))
    }
}
