//
//  QuoteFormatter.swift
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import UIKit

// Formatting of text inside a blockquote.
class QuoteFormatter: PreviewFormatter {
    override func handleLineBreak() -> FormatNode {
        return FormatNode("\n")
    }

    override func handleImage(using data: [String : JSONValue]?, draftyKey key: Int?) -> FormatNode {
        var attachment = Attachment(content: .image)
        let img = FormatNode()
        var filename = ""
        if let attr = data {
            let dims = CGFloat(UiUtils.kReplyThumbnailSize)
            if let bits = attr["val"]?.asData() {
                attachment.bits = bits
            } else if let ref = attr["ref"]?.asString() {
                attachment.ref = ref
                attachment.afterRefDownloaded = {
                    return $0.resize(
                        width: dims, height: dims, clip: true)
                }
            }
            attachment.mime = "image/jpeg"
            if let name = attr["name"]?.asString() {
                filename = UiUtils.previewFileName(from: name)
                attachment.name = name
            } else {
                filename = NSLocalizedString("Picture", comment: "Label shown next to an inline image")
            }
            attachment.size = attr["size"]?.asInt()
        }

        // Vertical alignment of the image to the middle of the text.
        attachment.offset = CGPoint(x: 0, y: min(QuoteFormatter.kDefaultFont.capHeight - CGFloat(UiUtils.kReplyThumbnailSize), 0) * 0.5)

        attachment.width = UiUtils.kReplyThumbnailSize
        attachment.height = UiUtils.kReplyThumbnailSize
        attachment.draftyEntityKey = key

        img.attachment(attachment)
        var children: [FormatNode] = []
        children.append(img)
        if !filename.isEmpty {
            let node = FormatNode(" " + filename)
            var attributes = defaultAttrs
            attributes[.font] = UIFont(name: "Courier", size: QuoteFormatter.kDefaultFont.pointSize - 0.5)!
            node.style(cstyle: attributes)
            children.append(node)
        }
        return FormatNode(children)
    }

    override func handleAttachment(using attr: [String: JSONValue]?, draftyKey _: Int?) -> FormatNode {
        var annotation: String
        if let filename = attr?["name"]?.asString() {
            annotation = UiUtils.previewFileName(from: filename)
        } else {
            annotation = NSLocalizedString("Attachment", comment: "Label shown next to an attachment")
        }
        return PreviewFormatter.annotatedIcon(iconName: "paperclip", localizedAnnotation: annotation)
    }

    override func handleMention(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        let node = FormatNode(nodes)
        if let uid = data?["val"]?.asString() {
            node.style(cstyle: [.foregroundColor: UiUtils.letterTileColor(for: uid, dark: true)])
        }
        return node
    }
}
