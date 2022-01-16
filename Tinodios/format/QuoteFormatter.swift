//
//  QuoteFormatter.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import UIKit

// Formatting of text inside a blockquote.
class QuoteFormatter: PreviewFormatter {
    static let kThumbnailImageDim = 32

    override func handleLineBreak() -> FormatNode {
        return FormatNode("\n")
    }

    override func handleImage(using data: [String : JSONValue]?, fromDraftyEntity key: Int?) -> FormatNode {
        var attachment = Attachment(content: .image)
        let img = FormatNode()
        var filename = ""
        if let attr = data {
            if let bits = attr["val"]?.asData() {
                attachment.bits = bits
            } else if let ref = attr["ref"]?.asString() {
                attachment.ref = ref
                attachment.afterRefDownloaded = {
                    return $0.resize(
                        width: CGFloat(UiUtils.kReplyThumbnailSize), height: CGFloat(UiUtils.kReplyThumbnailSize), clip: true)
                }
            }
            attachment.mime = attr["mime"]?.asString()
            if let name = attr["name"]?.asString() {
                filename = UiUtils.previewFileName(from: name)
            } else {
                filename = NSLocalizedString("Picture", comment: "Label shown next to an inline image")
            }
            attachment.size = attr["size"]?.asInt()
            attachment.width = QuoteFormatter.kThumbnailImageDim
            attachment.height = QuoteFormatter.kThumbnailImageDim
            attachment.draftyEntityKey = key
        }
        img.attachment(attachment)
        var children: [FormatNode] = []
        children.append(img)
        if !filename.isEmpty {
            let node = FormatNode(filename)
            node.style(cstyle: [.font: Constants.kDefaultFont.withTraits(traits: .traitItalic)])
            children.append(node)
        }
        return FormatNode(children)
    }

    override func handleAttachment(using attr: [String: JSONValue]?) -> FormatNode {
        var annotation: String
        if let filename = attr?["name"]?.asString() {
            annotation = UiUtils.previewFileName(from: filename)
        } else {
            annotation = NSLocalizedString("Attachment", comment: "Label shown next to an attachment")
        }
        return annotatedIcon(iconName: "attach-50", annotation: annotation, comment: "Attachment preview icon.")
    }
}
