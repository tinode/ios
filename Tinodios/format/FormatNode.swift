//
//  FormatNode.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import MobileCoreServices // For MIME -> UTI conversion
import UIKit
import TinodeSDK

// File or image attachment.
struct Attachment {
    enum AttachmentType {
        case data
        case image
        case button
        case quote
        case empty
    }

    var content: AttachmentType

    var bits: Data?
    var mime: String?
    var name: String?
    var ref: String?
    // Callback to run after the image has been downloaded from ref.
    var afterRefDownloaded: ((UIImage) -> UIImage?)?
    var size: Int?
    var width: Int?
    var height: Int?
    // Index of the entity in the original Drafty object.
    var draftyEntityKey: Int?
}

// Class representing Drafty as a tree of nodes with content and styles attached.
class FormatNode: CustomStringConvertible {
    internal enum Constants {
        /// Size of the document icon in attachments.
        static let kAttachmentIconSize = CGSize(width: 24, height: 32)
        /// URL and Button text color
        static let kLinkColor = UIColor(red: 0, green: 122/255, blue: 1, alpha: 1)
    }

    // Thrown by the formatting function when the length budget gets exceeded.
    // Param represents the maximum prefix fitting within the length budget.
    public enum LengthExceededError: Error {
        case runtimeError(NSAttributedString)
    }

    typealias CharacterStyle = [NSAttributedString.Key: Any]

    // A set of font traits to apply at the leaf level
    var cFont: UIFontDescriptor.SymbolicTraits?
    // Character style which can be applied over leaf or subtree
    var cStyle: CharacterStyle?
    // Paragraph-level style to apply to leaf or subtree
    var pStyle: NSMutableParagraphStyle?
    // Attachment. Apple is really bad at designing interfaces.
    var attachment: Attachment?
    // Attachment. Like text, it simply gets appended to the output attributed string.
    var preformattedAttachment: NSTextAttachment?

    // Leaf
    var text: String?

    // Subtree
    var children: [FormatNode]?

    required init() {
        text = nil
        children = nil
    }

    // Create unstyled node
    init(_ text: String) {
        self.text = text
    }

    init(_ nodes: [FormatNode]) {
        self.children = nodes
    }

    private init(style: CharacterStyle, nodes: [FormatNode]) {
        self.cStyle = style
        self.children = nodes
    }

    var description: String {
        return children?.description ?? "nil"
    }

    func style(cstyle: CharacterStyle) {
        cStyle = cstyle
    }

    func style(pstyle: NSMutableParagraphStyle) {
        pStyle = pstyle
    }

    func style(fontTraits: UIFontDescriptor.SymbolicTraits) {
        cFont = fontTraits
    }

    func attachment(_ attachment: Attachment) {
        self.attachment = attachment
    }

    func preformattedAttachment(_ attachment: NSTextAttachment) {
        self.preformattedAttachment = attachment
    }

    func append(_ child: FormatNode) {
        if children == nil { children = [] }
        children!.append(child)
    }

    var isEmpty: Bool {
        return children?.isEmpty ?? true
    }

    /// Simple representation of an attachment as plain string.
    private func attachmentToString(_ attachment: Attachment) -> String {
        switch attachment.content {
        case .image:
            return "[img ref=\(attachment.ref ?? "nil") \(attachment.name ?? "unnamed") \(attachment.width ?? 0)x\(attachment.height ?? 0) \(attachment.size ?? 0)B]"
        case .quote:
            fallthrough
        case .button:
            let entity = attachment.content == .quote ? "quote" : "btn"
            if let text = text {
                return "[\(entity) \(text)]"
            }
            if let children = children {
                var faceText = ""
                for child in children {
                    faceText += child.toString()
                }
                return "[\(entity) \(faceText)]"
            }
            return "[\(entity)]"
        case .empty:
            fallthrough
        case .data:
            var fname = attachment.name ?? "unnamed"
            if fname.count > 32 {
                fname = fname.prefix(14) + "…" + fname.suffix(14)
            }
            return "[att \(fname)]"
        }
    }

    private func makeFileAttachmentString(_ attachment: Attachment, withData bits: Data?, withRef ref: String?, defaultAttrs attributes: [NSAttributedString.Key: Any], maxSize size: CGSize) -> NSAttributedString {
        let attributed = NSMutableAttributedString()
        let baseFont = attributes[.font] as! UIFont
        attributed.beginEditing()

        // Get file description such as 'PDF Document'.
        let mimeType = attachment.mime ?? "application/octet-stream"
        let fileUti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType as CFString, nil)?.takeRetainedValue() ?? kUTTypeData
        let fileDesc = (UTTypeCopyDescription(fileUti)?.takeRetainedValue() as String?) ?? NSLocalizedString("Unknown type", comment: "Displayed when the type of attachment cannot be determined")
        // Get stock icon for the given file type.
        let fileIcon = UIImage.defaultIcon(forMime: mimeType, preferredWidth: baseFont.lineHeight * 0.8)

        // Using basic kUTTypeData to prevent iOS from displaying distorted previews.
        let tinode = Cache.tinode
        // The attachment is valid if it contains either data or a link to download the data.
        let isValid = bits != nil || ref != nil
        if isValid {
            let data = bits ?? Data(tinode.hostURL(useWebsocketProtocol: false)!.appendingPathComponent(ref!).absoluteString.utf8)
            let wrapper = NSTextAttachment(data: data, ofType: kUTTypeData as String)
            wrapper.bounds = CGRect(origin: CGPoint(x: 0, y: baseFont.capHeight - Constants.kAttachmentIconSize.height), size: Constants.kAttachmentIconSize)
            attributed.append(NSAttributedString(attachment: wrapper))
        }

        // Append document's file name.
        let originalFileName = attachment.name ?? "tinode_file_attachment"
        var fname = originalFileName
        // Heuristic for fitting file name in one line.
        let maxLen = Int(size.width) / 11
        if fname.count > maxLen {
            let visibleLen = (maxLen - 3) / 2
            fname = fname.prefix(visibleLen) + "…" + fname.suffix(visibleLen)
        }
        attributed.append(NSAttributedString(string: " "))
        attributed.append(NSAttributedString(string: fname, attributes: [NSAttributedString.Key.font: UIFont(name: "Courier", size: baseFont.pointSize)!]))

        // Append file size.
        if let size = attachment.size {
            // PDF Document · 2.0MB
            // \u{2009} because iOS is buggy and bugs go unfixed for years.
            // https://stackoverflow.com/questions/29041458/how-to-set-color-of-templated-image-in-nstextattachment
            attributed.append(NSAttributedString(string: "\u{2009}\n", attributes: [NSAttributedString.Key.font: baseFont]))

            let second = NSMutableAttributedString(string: "\(fileDesc) · \(UiUtils.bytesToHumanSize(Int64(size)))")
            second.beginEditing()

            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = Constants.kAttachmentIconSize.width + baseFont.capHeight * 0.25
            paragraph.lineSpacing = 0
            paragraph.lineHeightMultiple = 0.25
            second.addAttributes([NSAttributedString.Key.paragraphStyle: paragraph, NSAttributedString.Key.foregroundColor: UIColor.gray
            ], range: NSRange(location: 0, length: second.length))

            second.endEditing()
            attributed.append(second)
        }

        if isValid {
            // Insert linebreak then a clickable [↓ save] line
            attributed.append(NSAttributedString(string: "\u{2009}\n", attributes: [NSAttributedString.Key.font: baseFont]))

            let second = NSMutableAttributedString(string: "\u{2009}")
            second.beginEditing()

            // Add 'download file' icon
            let icon = NSTextAttachment()
            icon.image = fileIcon ?? UIImage(named: "download-24")?.withRenderingMode(.alwaysTemplate)
            icon.bounds = CGRect(origin: CGPoint(x: 0, y: -2), size: CGSize(width: baseFont.lineHeight * 0.8, height: baseFont.lineHeight * 0.8))
            second.append(NSAttributedString(attachment: icon))

            // Add "save" text.
            second.append(NSAttributedString(string: " save", attributes: [NSAttributedString.Key.font: baseFont]))

            // Add paragraph style and coloring
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = Constants.kAttachmentIconSize.width + baseFont.capHeight * 0.25
            paragraph.lineSpacing = 0
            paragraph.lineHeightMultiple = 0
            second.addAttributes([NSAttributedString.Key.paragraphStyle: paragraph, NSAttributedString.Key.foregroundColor: Constants.kLinkColor
            ], range: NSRange(location: 0, length: second.length))

            var baseUrl = URLComponents(string: "tinode://\(tinode.hostName)")!
            baseUrl.path = ref != nil ? "/large-attachment" : "/small-attachment"
            baseUrl.queryItems = [URLQueryItem(name: "filename", value: originalFileName)]

            second.addAttribute(.link, value: baseUrl.url! as Any, range: NSRange(location: 0, length: second.length))
            second.endEditing()
            attributed.append(second)
        }

        attributed.endEditing()
        return attributed
    }

    /// Create custom layout for attachments.
    private func attachmentToAttributed(_ attachment: Attachment, defaultAttrs attributes: [NSAttributedString.Key: Any], fontTraits: UIFontDescriptor.SymbolicTraits?, maxSize size: CGSize) -> NSAttributedString {
        switch attachment.content {
        // Image handling is easy.
        case .image:
            let url: URL?
            if let ref = attachment.ref {
                url = Utils.tinodeResourceUrl(from: ref)
            } else {
                url = nil
            }
            // tinode:// and mid: schemes are not real external URLs.
            let wrapper = url == nil || url?.scheme == "mid" || url?.scheme == "tinode" ? ImageTextAttachment() : AsyncTextAttachment(url: url!, afterDownloaded: attachment.afterRefDownloaded)
            wrapper.draftyEntityKey = attachment.draftyEntityKey

            var image: UIImage?
            if let bits = attachment.bits, let preview = UIImage(data: bits) {
                // FIXME: maybe cache result of converting Data to image (using topic+message_id as key).
                // KingfisherManager.shared.cache.store(T##image: KFCrossPlatformImage##KFCrossPlatformImage, forKey: T##String)
                image = preview
            }

            var originalSize: CGSize
            if let width = attachment.width, let height = attachment.height, width > 0 && height > 0 {
                // Sender provider valid width and height of the image.
                originalSize = CGSize(width: width, height: height)
            } else if let image = image {
                originalSize = image.size
            } else {
                originalSize = CGSize(width: UiUtils.kDefaultBitmapSize, height: UiUtils.kDefaultBitmapSize)
            }

            let scaledSize = UiUtils.sizeUnder(original: originalSize, fitUnder: size, scale: 1, clip: false).dst
            if image == nil {
                let iconName = attachment.ref != nil ? "image-wait" : "broken-image"
                // No need to scale the stock image.
                wrapper.image = UiUtils.placeholderImage(named: iconName, withBackground: nil, width: scaledSize.width, height: scaledSize.height)
            } else {
                wrapper.image = image
            }
            wrapper.bounds = CGRect(origin: .zero, size: scaledSize)

            (wrapper as? AsyncTextAttachment)?.startDownload(onError: UiUtils.placeholderImage(named: "broken-image", withBackground: image, width: scaledSize.width, height: scaledSize.height))

            return NSAttributedString(attachment: wrapper)

        case .quote, .button:
            let isButton = attachment.content == .button
            let faceText = NSMutableAttributedString()
            var entity: String
            // Change color of text from default to link color.
            var attrs = attributes

            if isButton {
                attrs[.foregroundColor] = Constants.kLinkColor
                entity = "button"
            } else {
                entity = "quote"
            }

            if let text = text {
                faceText.append(FormatNode.textToAttributed(text, defaultAttrs: attrs, fontTraits: fontTraits))
            } else if let children = children {
                for child in children {
                    faceText.append(try! child.toAttributed(withDefaultAttributes: attrs, fontTraits: fontTraits, fitIn: size))
                }
            } else {
                faceText.append(NSAttributedString(string: entity, attributes: attrs))
            }
            if isButton {
                return NSAttributedString(attachment: DraftyButtonAttachment(face: faceText, data: URL(string: attachment.ref!)))
            }
            return NSAttributedString(attachment: QuotedAttachment(quotedText: faceText, fitIn: size))

        // File attachment is harder: construct attributed string showing an attachment.
        case .data, .empty:
            return makeFileAttachmentString(attachment, withData: attachment.bits, withRef: attachment.ref, defaultAttrs: attributes, maxSize: size)
        }
    }

    /// Plain text to attributed string.
    public static func textToAttributed(_ text: String, defaultAttrs: [NSAttributedString.Key: Any], fontTraits: UIFontDescriptor.SymbolicTraits?) -> NSAttributedString {

        var attributes = defaultAttrs
        if let fontTraits = fontTraits {
            let font = defaultAttrs[NSAttributedString.Key.font] as! UIFont
            attributes[.font] = UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(fontTraits)!, size: font.pointSize)
        }

        return NSAttributedString(string: text, attributes: attributes)
    }

    /// Convert tree of nodes into a plain string.
    func toString() -> String {
        var str: String = ""
        // First check for attachments.
        if let attachment = self.attachment {
            // Image or file attachment
            str += attachmentToString(attachment)
        } else if let text = self.text {
            str += text
        } else if let children = self.children {
            // Process children.
            for child in children {
                str += child.toString()
            }
        }
        return str
    }

    /// Convert tree of nodes into an attributed string.
    func toAttributed(withDefaultAttributes attributes: [NSAttributedString.Key: Any], fontTraits parentFontTraits: UIFontDescriptor.SymbolicTraits?, fitIn size: CGSize, upToLength maxLength: Int = Int.max) throws -> NSAttributedString {

        // Font traits for this substring and all its children.
        var fontTraits: UIFontDescriptor.SymbolicTraits? = cFont
        if let parentFontTraits = parentFontTraits {
            if fontTraits != nil {
                fontTraits!.insert(parentFontTraits)
            } else {
                fontTraits = parentFontTraits
            }
        }

        var exceeded = false
        let attributed = NSMutableAttributedString()
        attributed.beginEditing()

        // First check for attachments.
        if let preAttachment = self.preformattedAttachment {
            attributed.append(NSAttributedString(attachment: preAttachment))
        } else if let attachment = self.attachment {
            // Image or file attachment
            attributed.append(attachmentToAttributed(attachment, defaultAttrs: attributes, fontTraits: fontTraits, maxSize: size))
        } else if let text = self.text {
            // Uniformly styled substring. Apply uniform font style.
            attributed.append(FormatNode.textToAttributed(text, defaultAttrs: attributes, fontTraits: fontTraits))
        }
        if attributed.length > maxLength {
            exceeded = true
            attributed.setAttributedString(attributed.attributedSubstring(from: NSRange(location: 0, length: maxLength)))
        }

        if !exceeded, self.attachment == nil, let children = self.children {
            do {
                // Pass calculated font styles to children.
                for child in children {
                    let curLen = attributed.length
                    attributed.append(try child.toAttributed(withDefaultAttributes: attributes, fontTraits: fontTraits, fitIn: size, upToLength: maxLength - curLen))
                }
            } catch LengthExceededError.runtimeError(let str) {
                exceeded = true
                attributed.append(str)
            }
        }

        // Then apply styles to the entire string.
        if let cstyle = cStyle {
            attributed.addAttributes(cstyle, range: NSRange(location: 0, length: attributed.length))
        } else if let pstyle = pStyle {
            attributed.addAttributes([.paragraphStyle: pstyle], range: NSRange(location: 0, length: attributed.length))
        }

        attributed.endEditing()
        if exceeded {
            throw LengthExceededError.runtimeError(attributed)
        }
        return attributed
    }
}

