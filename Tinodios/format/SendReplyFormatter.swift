//
//  SendReplyFormatter.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import UIKit


class SendReplyFormatter: QuoteFormatter {
    static let kQuotedReplyLength = 64

    // Keeps track of the chain of images which need to be asynchronously downloaded
    // and downsized.
    // var promise: PromisedReply<UIImage>?

    override func handleQuote(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        node.attachment(Attachment(content: .quote, fullWidth: true))
        return node
    }

    override func handleImage(using data: [String: JSONValue]?, draftyKey key: Int?) -> FormatNode {
        var attachment = Attachment(content: .image)
        let img = FormatNode()
        var filename = ""
        if let attr = data {
            let dims = CGFloat(UiUtils.kReplyThumbnailSize)
            if let bits = attr["val"]?.asData() {
                let thumbnail = UIImage(data: bits)?.resize(width: dims, height: dims, clip: true)
                attachment.bits = thumbnail?.pixelData(forMimeType: "image/jpeg")
                attachment.size = attachment.bits?.count
            } else if let ref = attr["ref"]?.asString() {
                attachment.ref = ref
                attachment.afterRefDownloaded = {
                    let resized = $0.resize(width: dims, height: dims, clip: true)
                    attachment.bits = resized?.pixelData(forMimeType: "image/jpeg")
                    attachment.size = attachment.bits?.count
                    return resized
                }
            }

            attachment.mime = "image/jpeg"
            if let name = attr["name"]?.asString() {
                filename = UiUtils.previewFileName(from: name)
                attachment.name = name
            } else {
                filename = NSLocalizedString("Picture", comment: "Label shown next to an inline image")
            }
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
}
