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
    var promise: PromisedReply<UIImage>?

    override func handleQuote(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        node.attachment(Attachment(content: .quote))
        return node
    }

    override func handleImage(using data: [String: JSONValue]?, fromDraftyEntity key: Int?) -> FormatNode {
        var attachment = Attachment(content: .image)
        let node = FormatNode()
        if let attr = data {
            let dims = CGFloat(UiUtils.kReplyThumbnailSize)
            if let bits = attr["val"]?.asData() {
                let thumbnail = UIImage(data: bits)?.resize(width: dims, height: dims, clip: true)
                attachment.bits = thumbnail?.pixelData(forMimeType: "image/jpeg")
                attachment.mime = "image/jpeg"
                attachment.size = attachment.bits?.count
            } else if let ref = attr["ref"]?.asString() {
                attachment.ref = ref
                attachment.afterRefDownloaded = {
                    let resized = $0.resize(width: dims, height: dims, clip: true)
                    attachment.bits = resized?.pixelData(forMimeType: "image/jpeg")
                    attachment.mime = "image/jpeg"
                    attachment.size = attachment.bits?.count
                    return resized
                }
            }
            attachment.name = attr["name"]?.asString()
            attachment.width = UiUtils.kReplyThumbnailSize
            attachment.height = UiUtils.kReplyThumbnailSize
        }
        attachment.draftyEntityKey = key
        node.attachment(attachment)
        return node
    }
}
