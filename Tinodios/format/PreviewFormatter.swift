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

    override init(defaultAttributes attrs: [NSAttributedString.Key : Any], defaultFont font: UIFont) {
        super.init(defaultAttributes: attrs, defaultFont: font)
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

    func annotatedIcon(iconName: String, localizedAnnotation: String? = nil) -> FormatNode {
        let icon = NSTextAttachment()
        icon.image = (UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(weight: .semibold)) ?? UIImage(named: iconName))?.withRenderingMode(.alwaysTemplate)
        var aspectRatio: CGFloat = 1
        if let size = icon.image?.size {
            aspectRatio = size.width / size.height
        }
        let baseFont = PreviewFormatter.kDefaultFont
        let height = baseFont.lineHeight * 0.8
        icon.bounds = CGRect(origin: CGPoint(x: 0, y: -2), size: CGSize(width: height * aspectRatio, height: height))

        var iconNode = FormatNode()
        iconNode.preformattedAttachment(icon)
        if let annotationStr = localizedAnnotation {
            iconNode = FormatNode([iconNode, FormatNode(" " + annotationStr)])
        }
        if let fg = defaultAttrs[.foregroundColor] as? UIColor {
            iconNode.style(cstyle: [.foregroundColor: fg])
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
        return annotatedIcon(iconName: "mic", localizedAnnotation: annotation)
    }

    override func handleImage(using attr: [String: JSONValue]?, draftyKey _: Int?) -> FormatNode {
        return annotatedIcon(iconName: "photo", localizedAnnotation: NSLocalizedString("Picture", comment: "Label shown next to an inline image"))
    }

    override func handleVideo(using attr: [String : JSONValue]?, draftyKey: Int?) -> FormatNode {
        var annotation: String
        if let attr = attr, let duration = attr["duration"]?.asInt() {
            annotation = PreviewFormatter.millisToTime(millis: duration, fixedMin: true)
        } else {
            annotation = "-:--"
        }
        return annotatedIcon(iconName: "play.circle", localizedAnnotation: annotation)
    }

    override func handleAttachment(using attr: [String: JSONValue]?, draftyKey _: Int?) -> FormatNode {
        guard let attr = attr else {
            return FormatNode()
        }

        if let mime = attr["mime"]?.asString(), mime == "application/json" {
            // Skip JSON attachments. They are not meant to be user-visible.
            return FormatNode()
        }

        return annotatedIcon(iconName: "paperclip", localizedAnnotation: NSLocalizedString("Attachment", comment: "Label shown next to an attachment"))
    }

    override func handleForm(_ nodes: [FormatNode]) -> FormatNode {
        var result = [annotatedIcon(iconName: "rectangle.3.group", localizedAnnotation: NSLocalizedString("Form", comment: "Label shown next to a form in preview")), FormatNode(": ")]
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

    override func handleVideoCall(content children: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        guard let data = data else {
            return handleUnknown(content: children, using: nil, draftyKey: nil)
        }

        let state = data["state"]?.asString() ?? ""
        let incoming = data["incoming"]?.asBool() ?? false
        let duration = data["duration"]?.asInt() ?? 0
        let annotation = duration > 0 ? AbstractFormatter.millisToTime(millis: duration) : AbstractFormatter.callStatusText(incoming: incoming, event: state)
        return annotatedIcon(iconName: "phone", localizedAnnotation: annotation)
    }

    override func handleUnknown(content _: [FormatNode], using _: [String: JSONValue]?, draftyKey _: Int?) -> FormatNode {
        return annotatedIcon(iconName: "puzzlepiece.extension", localizedAnnotation: NSLocalizedString("Unsupported", comment: "Label shown next to an unsupported Drafty format element"))
    }
}
