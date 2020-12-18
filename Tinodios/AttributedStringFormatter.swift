//
//  AttribFormatter.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//
//  Converts Drafty instance into attributed text suitable for display in UITextView

import MobileCoreServices // For MIME -> UTI conversion
import TinodeSDK
import UIKit

// iOS's support for styled strings is much weaker than Android's and web. Some styles cannot be nested. They have to be constructed and applied all at once at the leaf level.

/// Class which creates NSAttributedString with Drafty format applied.
class AttributedStringFormatter: DraftyFormatter {
    typealias Node = AttributedStringFormatter.TreeNode

    private enum Constants {
        static let kDefaultFont: UIFont = UIFont.preferredFont(forTextStyle: .body)
        /// Size of the document icon in attachments.
        static let kAttachmentIconSize = CGSize(width: 24, height: 32)
        /// URL and Button text color
        static let kLinkColor = UIColor(red: 0, green: 122/255, blue: 1, alpha: 1)
        /// Minumum width of the button in fontHeights/2
        static let kMinButtonWidth: Int = 10
        // Line hight multiplier in forms.
        static let kFormLineSpacing: CGFloat = 1.5
    }

    typealias CharacterStyle = [NSAttributedString.Key: Any]

    let defaultAttrs: [NSAttributedString.Key: Any]

    init(withDefaultAttributes attrs: [NSAttributedString.Key: Any]) {
        defaultAttrs = attrs
    }

    // Inline image
    private func handleImage(from node: TreeNode, with attr: [String : JSONValue]?) {
        var attachment = Attachment(content: .image)

        if let attr = attr {
            attachment.bits = attr["val"]?.asData()
            attachment.mime = attr["mime"]?.asString()
            attachment.name = attr["name"]?.asString()
            attachment.ref = attr["ref"]?.asString()
            attachment.size = attr["size"]?.asInt()
            attachment.width = attr["width"]?.asInt()
            attachment.height = attr["height"]?.asInt()
        }

        node.attachment(attachment)
    }

    private func handleAttachment(from node: TreeNode, with attr: [String : JSONValue]?) {
        if let attr = attr {
            let mimeType =  attr["mime"]?.asString()

            // Skip json attachments. They are not meant to be user-visible.
            if mimeType == "application/json" {
                return
            }

            let bits = attr["val"]?.asData()
            let ref = attr["ref"]?.asString()

            var attachment = Attachment(content: .data)
            if (bits == nil) && (ref == nil) {
                // Invalid attachment with no data.
                attachment.content = .empty
            }

            attachment.bits = bits
            attachment.ref = ref
            attachment.mime = mimeType
            attachment.name = attr["name"]?.asString()
            attachment.size = attr["size"]?.asInt()
            node.attachment(attachment)
            return
        }

        // Invalid attachment.
        node.attachment(Attachment(content: .empty))
    }

    private func handleButton(from node: TreeNode, with attr: [String : JSONValue]?) {
        guard let urlStr = AttributedStringFormatter.buttonDataAsUri(face: node, attr: attr), let url = URL(string: urlStr) else { return }

        let attachment = Attachment(content: .button, mime: nil, name: nil, ref: url.absoluteString, size: nil, width: nil, height: nil)
        node.attachment(attachment)
    }

    // Convert button payload to an URL.
    // NSAttributedString.Key.link wants payload to be NSURL.
    private static func buttonDataAsUri(face: TreeNode, attr: [String : JSONValue]?) -> String? {
        guard let attr = attr, let actionType = attr["act"]?.asString() else { return nil }
        var baseUrl: URLComponents
        switch actionType {
        case "url":
            guard let ref = attr["ref"]?.asString() else { return nil }
            guard let urlc = URLComponents(string: ref) else { return nil }
            guard urlc.scheme == "http" || urlc.scheme == "https" else { return nil }
            baseUrl = urlc
            if let name = attr["name"]?.asString() {
                let actionValue = attr["val"]?.asString() ?? "1"
                if baseUrl.queryItems == nil {
                    baseUrl.queryItems = []
                }
                baseUrl.queryItems!.append(URLQueryItem(name: name, value: actionValue))
            }
        case "pub":
            // Custom scheme usr to post back to the server:
            // tinode:default?name=value
            baseUrl = URLComponents()
            baseUrl.scheme = "tinode"
            baseUrl.host = ""
            baseUrl.path = "/post"
            baseUrl.queryItems = []
            baseUrl.queryItems!.append(URLQueryItem(name: "title", value: face.toString()))
            if let name = attr["name"]?.asString() {
                baseUrl.queryItems!.append(URLQueryItem(name: "name", value: name))
                let actionValue = attr["val"]?.asString() ?? "1"
                baseUrl.queryItems!.append(URLQueryItem(name: "val", value: actionValue))
            }
        default:
            return nil
        }

        return baseUrl.url?.absoluteString
    }

    // Construct a tree representing formatting styles and content.
    private func apply(tp: String?, attr: [String : JSONValue]?, children: [TreeNode]?, content: String?) -> TreeNode {
        // Create unstyled node
        var node = TreeNode(text: content, nodes: children)
        switch tp {
        case "ST":
            node.style(fontTraits: .traitBold)
        case "EM":
            node.style(fontTraits: .traitItalic)
        case "DL":
            node.style(cstyle: [NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.single.rawValue])
        case "CO":
            // .traitMonoSpace is not a real font trait. It cannot be applied to an arbitrary font. A real
            // monospaced font must be selected manually.
            let baseFont = defaultAttrs[.font] as! UIFont
            var attributes = defaultAttrs
            attributes[.font] = UIFont(name: "Courier", size: baseFont.pointSize)!
            node.style(cstyle: attributes)
        case "BR":
            node = TreeNode(content: "\n")
        case "LN":
            if let urlString = attr?["url"]?.asString(), let url = NSURL(string: urlString), url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" {
                node.style(cstyle: [NSAttributedString.Key.link: url])
            }
        case "MN": break // TODO: add fupport for @mentions
        case "HT": break // TODO: add support for #hashtangs
        case "HD": break // Hidden/ignored text
        case "IM":
            // Inline image
            handleImage(from: node, with: attr)
        case "EX":
            // Attachment
            handleAttachment(from: node, with: attr)
        case "BN":
            // Button
            handleButton(from: node, with: attr)
        case "FM":
            // Form
            if var children = node.children, !children.isEmpty {
                // Add line breaks between form elements: each direct descendant is a paragraph.
                for i in stride(from: children.count-1, to: 0, by: -1) {
                    children.insert(TreeNode(content: "\n"), at: i)
                }
                node.children = children
            }
        case "RW":
            // Form element formatting is dependent on element content.
            // No additional handling is needed.
            break
        default:
            break // Unknown formatting, treat as plain text
        }
        return node
    }

    func apply(tp: String?, attr: [String : JSONValue]?, content: [AttributedStringFormatter.TreeNode]) -> AttributedStringFormatter.TreeNode {
        return apply(tp: tp, attr: attr, children: content, content: nil)
    }

    func apply(tp: String?, attr: [String : JSONValue]?, content: String?) -> AttributedStringFormatter.TreeNode {
        return apply(tp: tp, attr: attr, children: nil, content: content)
    }

    /// Convert drafty object into NSAttributedString
    /// - Parameters:
    ///    - content: Drafty object to convert
    ///    - fitIn: maximum size of attached images.
    ///    - defaultAttrs: default attribues to apply to all otherwise unstyled content.
    ///    - textColor: default text color.
    public static func toAttributed(_ content: Drafty, fitIn maxSize: CGSize, withDefaultAttributes attributes: [NSAttributedString.Key : Any]? = nil) -> NSAttributedString {

        var attributes: [NSAttributedString.Key : Any] = attributes ?? [:]
        if attributes[.font] == nil {
            attributes[.font] = Constants.kDefaultFont
        }

        if content.isPlain {
            return NSMutableAttributedString(string: content.string, attributes: attributes)
        }

        let formatTree = content.format(formatter: AttributedStringFormatter(withDefaultAttributes: attributes))
        return formatTree.toAttributed(withDefaultAttributes: attributes, fontTraits: nil, fitIn: maxSize)
    }

    // File or image attachment.
    struct Attachment {
        enum AttachmentType {
            case data
            case image
            case button
            case empty
        }

        var content: AttachmentType

        var bits: Data?
        var mime: String?
        var name: String?
        var ref: String?
        var size: Int?
        var width: Int?
        var height: Int?
    }

    // Class representing Drafty as a tree of nodes with content and styles attached.
    class TreeNode : CustomStringConvertible {
        // Link to parent class
        weak var parent: AttributedStringFormatter!

        // A set of font traits to apply at the leaf level
        var cFont: UIFontDescriptor.SymbolicTraits?
        // Character style which can be applied over leaf or subtree
        var cStyle: CharacterStyle?
        // Paragraph-level style to apply to leaf or subtree
        var pStyle: NSMutableParagraphStyle?
        // Attachment. Apple is really bad at designing interfaces.
        var attachment: Attachment?

        // Leaf
        var text: String?
        // Subtree
        var children: [TreeNode]?

        private init() {
            text = nil
            children = nil
        }

        // Create unstyled node
        init(text: String?, nodes: [TreeNode]?) {
            self.text = text
            self.children = nodes
        }

        private init(style: CharacterStyle, nodes: [TreeNode]) {
            self.cStyle = style
            self.text = nil
            self.children = nodes
        }

        convenience init(content: String) {
            self.init(text: content, nodes: nil)
        }

        init(content: [TreeNode]) {
            self.children = content
        }

        init(content: TreeNode) {
            if self.children == nil {
                self.children = []
            }
            self.children!.append(content)
        }

        var description: String {
            return text ?? children?.description ?? "nil"
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

        func addNode(node: TreeNode?) {
            guard let node = node else { return }

            if children == nil {
                children = []
            }
            children!.append(node)
        }

        func addNode(content: String?) {
            guard let content = content else { return }

            addNode(node: TreeNode(content: content))
        }

        var isEmpty: Bool {
            return (text?.isEmpty ?? true) && (children?.isEmpty ?? true)
        }

        /// Simple representation of an attachment as plain string.
        private func attachmentToString(_ attachment: Attachment) -> String {
            switch attachment.content {
            case .image:
                return "[img \(attachment.name ?? "unnamed")]"
            case .button:
                if let text = text {
                    return "[btn \(text)]"
                }
                if let children = children {
                    var faceText = ""
                    for child in children {
                        faceText += child.toString()
                    }
                    return "[btn \(faceText)]"
                }
                return "[button]"
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

        private func makeFileAttachmentString(_ attachment: Attachment, withData bits: Data?, withRef ref: String?, defaultAttrs attributes: [NSAttributedString.Key : Any], maxSize size: CGSize) -> NSAttributedString {
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
            attributed.append(NSAttributedString(string: fname, attributes: [NSAttributedString.Key.font : UIFont(name: "Courier", size: baseFont.pointSize)!]))

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
                second.addAttributes([NSAttributedString.Key.paragraphStyle : paragraph, NSAttributedString.Key.foregroundColor : UIColor.gray,
                ], range: NSRange(location: 0, length: second.length))

                second.endEditing()
                attributed.append(second)
            }

            if isValid {
                // Insert linebreak then a clickable [↓ save] line
                attributed.append(NSAttributedString(string: "\u{2009}\n", attributes: [NSAttributedString.Key.font : baseFont]))

                let second = NSMutableAttributedString(string: "\u{2009}")
                second.beginEditing()

                // Add 'download file' icon
                let icon = NSTextAttachment()
                icon.image = fileIcon ?? UIImage(named: "download-24")?.withRenderingMode(.alwaysTemplate)
                icon.bounds = CGRect(origin: CGPoint(x: 0, y: -2), size: CGSize(width: baseFont.lineHeight * 0.8, height: baseFont.lineHeight * 0.8))
                second.append(NSAttributedString(attachment: icon))

                // Add "save" text.
                second.append(NSAttributedString(string: " save", attributes: [NSAttributedString.Key.font : baseFont]))

                // Add paragraph style and coloring
                let paragraph = NSMutableParagraphStyle()
                paragraph.firstLineHeadIndent = Constants.kAttachmentIconSize.width + baseFont.capHeight * 0.25
                paragraph.lineSpacing = 0
                paragraph.lineHeightMultiple = 0
                second.addAttributes([NSAttributedString.Key.paragraphStyle : paragraph, NSAttributedString.Key.foregroundColor : Constants.kLinkColor,
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
        private func attachmentToAttributed(_ attachment: Attachment, defaultAttrs attributes: [NSAttributedString.Key : Any], fontTraits: UIFontDescriptor.SymbolicTraits?, maxSize size: CGSize) -> NSAttributedString {
            switch attachment.content {
            // Image handling is easy.
            case .image:
                let tinode = Cache.tinode
                let url: URL?
                if let ref = attachment.ref {
                    url = URL(string: ref, relativeTo: tinode.baseURL(useWebsocketProtocol: false))
                } else {
                    url = nil
                }
                // tinode:// and mid: schemes are not real external URLs.
                let wrapper = url == nil || url?.scheme == "mid" || url?.scheme == "tinode" ? NSTextAttachment() : AsyncTextAttachment(url: url!)

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

                var scaledSize: CGSize
                if image == nil {
                    let iconName = attachment.ref != nil ? "image-wait" : "broken-image"
                    // No need to scale the stock image.
                    wrapper.image = UiUtils.placeholderImage(named: iconName, withBackground: nil, width: size.width, height: size.height)
                    scaledSize = size
                } else {
                    wrapper.image = image
                    scaledSize = UiUtils.sizeUnder(original: originalSize, fitUnder: size, scale: 1, clip: false).dst
                }
                wrapper.bounds = CGRect(origin: .zero, size: scaledSize)

                (wrapper as? AsyncTextAttachment)?.startDownload(onError: UiUtils.placeholderImage(named: "broken-image", withBackground: image, width: scaledSize.width, height: scaledSize.height))

                return NSAttributedString(attachment: wrapper)

            // Button is also not too hard
            case .button:
                let faceText = NSMutableAttributedString()
                // Change color of text from default to link color.
                var attrs = attributes
                attrs[.foregroundColor] = Constants.kLinkColor
                if let text = text {
                    faceText.append(textToAttributed(text, defaultAttrs: attrs, fontTraits: fontTraits))
                } else if let children = children {
                    for child in children {
                        faceText.append(child.toAttributed(withDefaultAttributes: attrs, fontTraits: fontTraits, fitIn: size))
                    }
                } else {
                    faceText.append(NSAttributedString(string: "button", attributes: attrs))
                }
                return NSAttributedString(attachment: DraftyButtonAttachment(face: faceText, data: URL(string: attachment.ref!)))

            // File attachment is harder: construct attributed string showing an attachment.
            case .data, .empty:
                return makeFileAttachmentString(attachment, withData: attachment.bits, withRef: attachment.ref, defaultAttrs: attributes, maxSize: size)
            }
        }

        /// Plain text to attributed string.
        private func textToAttributed(_ text: String, defaultAttrs: [NSAttributedString.Key : Any], fontTraits: UIFontDescriptor.SymbolicTraits?) -> NSAttributedString {

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
        func toAttributed(withDefaultAttributes attributes: [NSAttributedString.Key : Any], fontTraits parentFontTraits: UIFontDescriptor.SymbolicTraits?, fitIn size: CGSize) -> NSAttributedString {

            // Font traits for this substring and all its children.
            var fontTraits: UIFontDescriptor.SymbolicTraits? = cFont
            if let parentFontTraits = parentFontTraits {
                if fontTraits != nil {
                    fontTraits!.insert(parentFontTraits)
                } else {
                    fontTraits = parentFontTraits
                }
            }

            let attributed = NSMutableAttributedString()
            attributed.beginEditing()

            // First check for attachments.
            if let attachment = self.attachment {
                // Image or file attachment
                attributed.append(attachmentToAttributed(attachment, defaultAttrs: attributes, fontTraits: fontTraits, maxSize: size))
            } else if let text = self.text {
                // Uniformly styled substring. Apply uniform font style.
                attributed.append(textToAttributed(text, defaultAttrs: attributes, fontTraits: fontTraits))
            } else if let children = self.children {
                // Pass calculated font styles to children.
                for child in children {
                    attributed.append(child.toAttributed(withDefaultAttributes: attributes, fontTraits: fontTraits, fitIn: size))
                }
            }

            // Then apply styles to the entire string.
            if let cstyle = cStyle {
                attributed.addAttributes(cstyle, range: NSRange(location: 0, length: attributed.length))
            } else if let pstyle = pStyle {
                attributed.addAttributes([.paragraphStyle: pstyle], range: NSRange(location: 0, length: attributed.length))
            }

            attributed.endEditing()
            return attributed
        }
    }
}
