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
    private enum Constants {
        static let kSecondaryColorAlpha: CGFloat = 0.8
    }

    override init(defaultAttributes attrs: [NSAttributedString.Key: Any]) {
        var attributes = attrs
        if let fg = attrs[.foregroundColor] as? UIColor {
            attributes[.foregroundColor] = fg.withAlphaComponent(Constants.kSecondaryColorAlpha)
        }
        super.init(defaultAttributes: attributes)
    }

    override init(defaultAttributes attrs: [NSAttributedString.Key: Any], defaultFont font: UIFont) {
        var attributes = attrs
        if let fg = attrs[.foregroundColor] as? UIColor {
            attributes[.foregroundColor] = fg.withAlphaComponent(Constants.kSecondaryColorAlpha)
        }
        super.init(defaultAttributes: attributes, defaultFont: font)
    }

    override func handleLineBreak() -> FormatNode {
        return FormatNode("\n")
    }

    private func createMediaAttachment(fromAttr data: [String : JSONValue]?, draftyKey key: Int?,
                                       bitsField: String, refField: String,
                                       thumbnailWidth: Int, thumbnailHeight: Int, isVideo: Bool) -> FormatNode {
        var attachment = Attachment(content: .image)
        let img = FormatNode()
        var filename = ""
        var actualSize: CGSize = CGSize(width: UiUtils.kReplyThumbnailSize, height: UiUtils.kReplyThumbnailSize)
        if let attr = data {
            if let w = attr["width"]?.asInt(), let h = attr["height"]?.asInt() {
                actualSize = UiUtils.sizeUnder(original: CGSize(width: w, height: h), fitUnder: CGSize(width: thumbnailWidth, height: thumbnailHeight), scale: 1, clip: false).dst
            }
            if let bits = attr[bitsField]?.asData() {
                attachment.bits = bits
            } else if let ref = attr[refField]?.asString() {
                attachment.ref = ref
                attachment.afterRefDownloaded = {
                    return $0.resize(
                        width: CGFloat(thumbnailWidth), height: CGFloat(thumbnailHeight), clip: !isVideo)
                }
            }
            attachment.mime = "image/jpeg"
            if let name = attr["name"]?.asString() {
                filename = UiUtils.previewFileName(from: name)
                attachment.name = name
            } else {
                filename = isVideo ?
                    NSLocalizedString("Video", comment: "Label shown next to an inline video") :
                    NSLocalizedString("Picture", comment: "Label shown next to an inline image")
            }
            attachment.size = attr["size"]?.asInt()
        }

        // Vertical alignment of the image to the middle of the text.
        attachment.offset = CGPoint(x: 0, y: min(QuoteFormatter.kDefaultFont.capHeight - actualSize.height, 0) * 0.5)

        attachment.width = Int(actualSize.width)
        attachment.height = Int(actualSize.height)
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

    override func handleImage(using data: [String : JSONValue]?, draftyKey key: Int?) -> FormatNode {
        return createMediaAttachment(
            fromAttr: data, draftyKey: key, bitsField: "val", refField: "ref",
            thumbnailWidth: UiUtils.kReplyThumbnailSize, thumbnailHeight: UiUtils.kReplyThumbnailSize, isVideo: false)
    }

    override func handleAttachment(using attr: [String: JSONValue]?, draftyKey _: Int?) -> FormatNode {
        var annotation: String
        if let filename = attr?["name"]?.asString() {
            annotation = UiUtils.previewFileName(from: filename)
        } else {
            annotation = NSLocalizedString("Attachment", comment: "Label shown next to an attachment")
        }
        return annotatedIcon(iconName: "paperclip", localizedAnnotation: annotation)
    }

    override func handleVideo(using data: [String : JSONValue]?, draftyKey key: Int?) -> FormatNode {
        return createMediaAttachment(
            fromAttr: data, draftyKey: key, bitsField: "preview", refField: "preref",
            thumbnailWidth: UiUtils.kReplyVideoThumbnailWidth, thumbnailHeight: UiUtils.kReplyThumbnailSize,
            isVideo: true)
    }

    override func handleMention(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        let node = FormatNode(nodes)
        if let uid = data?["val"]?.asString() {
            node.style(cstyle: [.foregroundColor: UiUtils.letterTileColor(for: uid, dark: true)])
        }
        return node
    }
}
