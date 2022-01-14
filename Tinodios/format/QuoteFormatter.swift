//
//  QuoteFormatter.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import UIKit

// Formatting of a text inside quote.
class QuoteFormatter: PreviewFormatter {
    static let kThumbnailImageDim = 32

    override func handleLineBreak() -> FormatNode {
        return FormatNode("\n")
    }

    override func handleImage(using attr: [String : JSONValue]?, fromDraftyEntity key: Int?) -> FormatNode {
        let img = FormatNode()
        var attachment = Attachment(content: .image)
        var filename = ""
        if let attr = attr {
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
                filename = "Picture"
            }
            attachment.size = attr["size"]?.asInt()
            attachment.width = QuoteFormatter.kThumbnailImageDim
            attachment.height = QuoteFormatter.kThumbnailImageDim
        }
        img.attachment(attachment)
        var children = [FormatNode]()
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
            annotation = "Attachment"
        }
        return annotatedIcon(iconName: "attach-50", annotation: annotation, comment: "Attachment preview icon.")
    }
}
