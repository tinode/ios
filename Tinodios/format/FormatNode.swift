//
//  FormatNode.swift
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
        case audio
        case data
        case image
        case button
        case quote
        case empty
        case unkn

        var description: String {
          get {
            switch self {
            case .audio:
                return "audio"
            case .data:
                return "data"
            case .image:
                return "image"
            case .button:
                return "button"
            case .quote:
                return "quote"
            case .empty:
                return "empty"
            case .unkn:
                return "unkn"
            }
          }
        }
    }

    var content: AttachmentType

    // Literal payload
    var bits: Data?
    // Reference to payload
    var ref: String?
    // Reference to app or system icon.
    var icon: String?
    var mime: String?
    var name: String?
    // Callback to run after the image has been downloaded from ref.
    var afterRefDownloaded: ((UIImage) -> UIImage?)?
    var size: Int?
    var width: Int?
    var height: Int?
    // Image offset from the origin.
    var offset: CGPoint?
    // Audio duration
    var duration: Int?
    // Audio preview.
    var preview: Data?
    // Draw background over the entire available width, not just under the text (quoted text).
    var fullWidth: Bool?
    // Index of the entity in the original Drafty object.
    var draftyEntityKey: Int?
}

// Class representing Drafty as a tree of nodes with content and styles attached.
class FormatNode: CustomStringConvertible {
    internal enum Constants {
        /// Size of the document icon in attachments.
        static let kAttachmentIconSize = CGSize(width: 24, height: 32)
        /// Size of the play/pause icon (square)
        static let kPlayIconSize: CGFloat = 28
        /// Size of the audio wave.
        static let kWaveSize = CGSize(width: 144, height: 32)
        /// URL and Button text color
        static let kLinkColor = UIColor.link //(red: 0, green: 122/255, blue: 1, alpha: 1)
        static let kQuoteTextColorAdj = 0.7 // Adjustment to font alpha in quote to make it less prominent.
        static let kPlayButtonColorAdj = 0.6 // Adjustment to alpha for showing Play/Pause buttons.
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

    // Create unstyled leaf node.
    init(_ text: String) {
        self.text = text
    }

    // Unstyled node with one or more subnodes.
    init(_ nodes: [FormatNode]) {
        if nodes.count > 1 {
            self.children = nodes
        } else if nodes.count == 1 {
            // Just copy the single child node to self.
            self.cFont = nodes[0].cFont
            self.cStyle = nodes[0].cStyle
            self.pStyle = nodes[0].pStyle
            self.attachment = nodes[0].attachment
            self.preformattedAttachment = nodes[0].preformattedAttachment
            self.text = nodes[0].text
            self.children = nodes[0].children
        }
    }

    private init(style: CharacterStyle, nodes: [FormatNode]) {
        self.cStyle = style
        self.children = nodes
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
        if text != nil {
            children!.append(FormatNode(text!))
            text = nil
        }
        children!.append(child)
    }

    var isEmpty: Bool {
        return text == nil && (children?.isEmpty ?? true) && attachment == nil
    }

    /// Simple representation of an attachment as plain string.
    private func attachmentDescription(_ attachment: Attachment) -> String {
        switch attachment.content {
        case .audio:
            return "{audio ref=\(attachment.ref ?? "nil") bits.count=\(attachment.bits?.count ?? -1) \(attachment.name ?? "unnamed") \(attachment.duration ?? 0)ms \(attachment.size ?? 0)B}"
        case .image:
            return "{img ref=\(attachment.ref ?? "nil") bits.count=\(attachment.bits?.count ?? -1) \(attachment.name ?? "unnamed") \(attachment.width ?? 0)x\(attachment.height ?? 0) \(attachment.size ?? 0)B}"
        case .quote:
            fallthrough
        case .button:
            let entity = attachment.content.description
            if let text = text {
                return "{\(entity): '\(text)'}"
            } else if let children = children {
                var faceText = ""
                for child in children {
                    faceText += child.description
                }
                return "{\(entity): [\(faceText)]}"
            }
            return "{\(entity)}"
        case .empty:
            return "{empty}"
        case .data:
            var fname = attachment.name ?? "unnamed"
            if fname.count > 32 {
                fname = fname.prefix(14) + "…" + fname.suffix(14)
            }
            return "{att: '\(fname)'}"
        case .unkn:
            return "{unkn}"
        }
    }

    // File attachment, including attachment with no data.
    private func createFileAttachmentString(_ attachment: Attachment, withData bits: Data?, withRef ref: String?, defaultAttrs attributes: [NSAttributedString.Key: Any], maxSize size: CGSize) -> NSAttributedString {
        let attributed = NSMutableAttributedString()
        let baseFont = attributes[.font] as! UIFont
        attributed.beginEditing()

        // Get file description such as 'PDF Document'.
        let mimeType = attachment.mime ?? "application/octet-stream"
        let fileUti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType as CFString, nil)?.takeRetainedValue() ?? kUTTypeData
        let fileDesc = (UTTypeCopyDescription(fileUti)?.takeRetainedValue() as String?) ?? NSLocalizedString("Unknown type", comment: "Displayed when the type of attachment cannot be determined")

        // Using basic kUTTypeData to prevent iOS from displaying distorted previews.
        let tinode = Cache.tinode
        // The attachment is valid if it contains either data or a link to download the data.
        let isValid = bits != nil || ref != nil
        if isValid {
            // TODO: use mime-specific file icon:
            // let fileIcon = UIImage.defaultIcon(forMime: mimeType, preferredWidth: baseFont.lineHeight * 0.8)
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

        // PDF Document · 2.0MB
        // \u{2009} because iOS is buggy and bugs go unfixed for years.
        // https://stackoverflow.com/questions/29041458/how-to-set-color-of-templated-image-in-nstextattachment
        attributed.append(NSAttributedString(string: "\u{2009}\n", attributes: [NSAttributedString.Key.font: baseFont]))

        let second = NSMutableAttributedString(string: "\(fileDesc)")
        second.beginEditing()

        if let size = attachment.size {
            // Append file size.
            second.append(NSAttributedString(string: " · \(UiUtils.bytesToHumanSize(Int64(size)))"))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = Constants.kAttachmentIconSize.width + baseFont.capHeight * 0.25
        paragraph.lineSpacing = 0
        paragraph.lineHeightMultiple = 0.25
        second.addAttributes([NSAttributedString.Key.paragraphStyle: paragraph, NSAttributedString.Key.foregroundColor: UIColor.gray
        ], range: NSRange(location: 0, length: second.length))

        second.endEditing()
        attributed.append(second)

        if isValid {
            // Insert linebreak then a clickable [↓ save] line
            attributed.append(NSAttributedString(string: "\u{2009}\n", attributes: [NSAttributedString.Key.font: baseFont]))

            let second = NSMutableAttributedString(string: "\u{2009}")
            second.beginEditing()

            // Add 'download file' icon
            let icon = NSTextAttachment()
            icon.image = UIImage(named: "download")?.withRenderingMode(.alwaysTemplate)
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
            baseUrl.path = ref != nil ? "/attachment/large" : "/attachment/small"
            baseUrl.queryItems = [URLQueryItem(name: "filename", value: originalFileName), URLQueryItem(name: "key", value: (attachment.draftyEntityKey != nil ? String(attachment.draftyEntityKey!) : nil))]

            second.addAttribute(.link, value: baseUrl.url! as Any, range: NSRange(location: 0, length: second.length))
            second.endEditing()
            attributed.append(second)
        }

        attributed.endEditing()
        return attributed
    }

    private func createAudioAttachmentString(_ attachment: Attachment, withData bits: Data?, withRef ref: String?, defaultAttrs attributes: [NSAttributedString.Key: Any], maxSize size: CGSize) -> NSAttributedString {

        let baseFont = attributes[.font] as! UIFont
        var baseUrl = URLComponents(string: "tinode://\(ref != nil ? "/audio/large" : "/audio/small")")!
        baseUrl.queryItems = [URLQueryItem(name: "key", value: (attachment.draftyEntityKey != nil ? String(attachment.draftyEntityKey!) : nil))]

        let attributed = NSMutableAttributedString(string: "\u{2009}")
        attributed.beginEditing()

        var attrs = attributes
        if let fg = attributes[.foregroundColor] as? UIColor {
            attrs[.foregroundColor] = fg.withAlphaComponent(Constants.kPlayButtonColorAdj)
        }

        // Play icon.
        let play = MultiImageTextAttachment(images: [UIImage(named: "play.circle.fill")!.withRenderingMode(.alwaysTemplate), UIImage(named: "pause.circle")!.withRenderingMode(.alwaysTemplate)])
        play.type = "audio/toggle-play"
        play.draftyEntityKey = attachment.draftyEntityKey
        play.delegate = PlayTextAttachmentDelegate(parent: play)
        play.bounds = CGRect(origin: CGPoint(x: 0, y: -2), size: CGSize(width: Constants.kPlayIconSize, height: Constants.kPlayIconSize))

        var second = NSMutableAttributedString()
        second.beginEditing()
        second.append(NSAttributedString(attachment: play))
        second.addAttributes(attrs, range: NSRange(location: 0, length: attributed.length))
        second.endEditing()

        attributed.append(second)

        let wave = WaveTextAttachment(frame: CGRect(origin: CGPoint(x: 0, y: 0), size: Constants.kWaveSize), data: attachment.preview)
        wave.type = "audio/seek"
        wave.draftyEntityKey = attachment.draftyEntityKey
        wave.delegate = WaveTextAttachmentDelegate(parent: wave)
        if let duration = attachment.duration, duration > 0 {
            wave.duration = duration
        }
        if let fg = attributes[.foregroundColor] as? UIColor {
            wave.pastBarColor = fg.withAlphaComponent(0.7).cgColor
            wave.futureBarColor = fg.withAlphaComponent(0.5).cgColor
            wave.update(recalc: false)
        }
        attributed.append(NSAttributedString(attachment: wave))

        // Linebreak.
        attributed.append(NSAttributedString(string: "\u{2009}\n", attributes: [NSAttributedString.Key.font: baseFont]))

        // Second line: duration
        let duration = attachment.duration != nil ? AbstractFormatter.millisToTime(millis: attachment.duration!) : "-:--"
        second = NSMutableAttributedString(string: duration)
        second.beginEditing()
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = Constants.kPlayIconSize + baseFont.capHeight * 0.25
        paragraph.lineSpacing = 0
        paragraph.lineHeightMultiple = 0.5
        var strAttrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key.paragraphStyle: paragraph]
        if let fg = attributes[.foregroundColor] {
            strAttrs[NSAttributedString.Key.foregroundColor] = fg
        }
        second.addAttributes(strAttrs, range: NSRange(location: 0, length: second.length))
        second.endEditing()

        attributed.append(second)

        attributed.endEditing()
        return attributed
    }

    /// Create custom layout for attachments.
    private func attachmentToAttributed(_ attachment: Attachment, defaultAttrs attributes: [NSAttributedString.Key: Any], fontTraits: UIFontDescriptor.SymbolicTraits?, maxSize size: CGSize) -> NSAttributedString {
        switch attachment.content {

        case .audio:
            return createAudioAttachmentString(attachment, withData: attachment.bits, withRef: attachment.ref, defaultAttrs: attributes, maxSize: size)
        case .image:
            // Image handling is easy.

            let url: URL?
            if let ref = attachment.ref {
                url = Utils.tinodeResourceUrl(from: ref)
            } else {
                url = nil
            }
            // tinode:// and mid: schemes are not real external URLs.
            let wrapper = (url == nil || url!.scheme == "mid" || url!.scheme == "tinode") ? EntityTextAttachment() : AsyncImageTextAttachment(url: url!, afterDownloaded: attachment.afterRefDownloaded)
            wrapper.type = "image"
            wrapper.draftyEntityKey = attachment.draftyEntityKey

            var image: UIImage?
            if let bits = attachment.bits, let preview = UIImage(data: bits) {
                // FIXME: maybe cache result of converting Data to image (using topic+message_id as key).
                // KingfisherManager.shared.cache.store(T##image: KFCrossPlatformImage##KFCrossPlatformImage, forKey: T##String)
                image = preview
            } else if let iconNamed = attachment.icon {
                image = UIImage(named: iconNamed)
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
            wrapper.bounds = CGRect(origin: attachment.offset ?? .zero, size: scaledSize)

            (wrapper as? AsyncImageTextAttachment)?.startDownload(onError: UiUtils.placeholderImage(named: "broken-image", withBackground: image, width: scaledSize.width, height: scaledSize.height))

            return NSAttributedString(attachment: wrapper)

        case .quote, .button:
            let isButton = attachment.content == .button
            let faceText = NSMutableAttributedString()
            var entity: String
            // Change color of text from default to link color.
            var attrs = attributes

            if isButton {
                attrs[.foregroundColor] = Constants.kLinkColor
                entity = NSLocalizedString("button", comment: "Text written on button face when all else fails.")
            } else {
                if let fg = attributes[.foregroundColor] as? UIColor {
                    attrs[.foregroundColor] = fg.withAlphaComponent(Constants.kQuoteTextColorAdj)
                }
                // Quote: just display nothing.
                entity = " "
            }

            if let text = text {
                faceText.append(FormatNode.textToAttributed(text, defaultAttrs: attrs, fontTraits: fontTraits))
            } else if let children = children {
                for child in children {
                    faceText.append(try! child.toAttributed(withAttributes: attrs, fontTraits: fontTraits, fitIn: size))
                }
            } else {
                faceText.append(NSAttributedString(string: entity, attributes: attrs))
            }
            if isButton {
                return NSAttributedString(attachment: ButtonAttachment(face: faceText, data: URL(string: attachment.ref!)))
            }
            return NSAttributedString(attachment: QuotedAttachment(quotedText: faceText, fitIn: size, fullWidth: attachment.fullWidth ?? false))

        // File attachment is harder: construct attributed string showing an attachment.
        case .data, .empty:
            return createFileAttachmentString(attachment, withData: attachment.bits, withRef: attachment.ref, defaultAttrs: attributes, maxSize: size)
        case .unkn:
            let attributed = NSMutableAttributedString(string: "\u{2009}")
            attributed.beginEditing()

            let icon = NSTextAttachment()
            icon.image = UIImage(systemName: "puzzlepiece.extension")?.withRenderingMode(.alwaysTemplate)
            let baseFont = attributes[.font] as! UIFont
            icon.bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: CGSize(width: baseFont.lineHeight, height: baseFont.lineHeight))

            attributed.append(NSAttributedString(attachment: icon))
            attributed.append(NSAttributedString(string: " "))

            if let text = text {
                attributed.append(FormatNode.textToAttributed(text, defaultAttrs: attributes, fontTraits: fontTraits))
            } else if let children = children {
                for child in children {
                    attributed.append(try! child.toAttributed(withAttributes: attributes, fontTraits: fontTraits, fitIn: size))
                }
            } else {
                attributed.append(NSAttributedString(string: NSLocalizedString("Unsupported", comment: "Unsupported (unknown) Drafty tag"), attributes: attributes))
            }

            attributed.endEditing()
            return attributed
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

    /// Convert tree of nodes into a string useful for debugging.
    var description: String {
        var str: String = ""
        // First check for attachments.
        if let preformatted = preformattedAttachment {
            str += "[pf: \(preformatted.description)]"
        }
        if let attachment = self.attachment {
            // Image or file attachment
            str += attachmentDescription(attachment)
        }
        if let text = self.text {
            str += "'\(text)'"
        } else if let children = self.children {
            // Process children.
            str += "["
            for child in children {
                str += child.description
            }
            str += "]"
        }
        return "{\(str)}"
    }

    /// Convert tree of nodes into a plain string.
    func toString() -> String {
        var str: String = ""
        // First check for attachments.
        if let attachment = self.attachment {
            // Image or file attachment
            str += attachmentDescription(attachment)
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
    func toAttributed(withAttributes attributes: [NSAttributedString.Key: Any], fontTraits parentFontTraits: UIFontDescriptor.SymbolicTraits?, fitIn size: CGSize) throws -> NSAttributedString {

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
            // Attachment.
            attributed.append(attachmentToAttributed(attachment, defaultAttrs: attributes, fontTraits: fontTraits, maxSize: size))
        } else if let text = self.text {
            // Uniformly styled substring. Apply uniform font style.
            attributed.append(FormatNode.textToAttributed(text, defaultAttrs: attributes, fontTraits: fontTraits))
        }

        if self.attachment == nil, let children = self.children {
            do {
                // Pass calculated font styles to children.
                for child in children {
                    attributed.append(try child.toAttributed(withAttributes: attributes, fontTraits: fontTraits, fitIn: size))
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

class WaveTextAttachmentDelegate: EntityTextAttachmentDelegate {
    weak var parent: EntityTextAttachment?

    init(parent: EntityTextAttachment) {
        self.parent = parent
    }

    public func action(_ value: String, payload: Any? = nil) {
        guard let wave = (self.parent as? WaveTextAttachment) else  { return }
        switch value {
        case "play":
            wave.play()
        case "pause":
            wave.pause()
        case "reset":
            wave.reset()
        case "seek":
            if let pos = payload as? Float {
                wave.seekTo(pos)
            }
        default:
            // Unknown action, ignore.
            break
        }
    }
}

class PlayTextAttachmentDelegate: EntityTextAttachmentDelegate {
    weak var parent: EntityTextAttachment?

    init(parent: EntityTextAttachment) {
        self.parent = parent
    }

    public func action(_ value: String, payload: Any? = nil) {
        guard let playButton = (parent as? MultiImageTextAttachment) else { return }
        switch value {
        case "play":
            playButton.setFrame(1)
        case "pause":
            playButton.setFrame(0)
        case "reset":
            playButton.reset()
        default:
            // Unsupported action like "seek", ignore.
            break
        }
    }
}
