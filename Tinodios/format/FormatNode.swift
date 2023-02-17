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
    enum AttachmentType: Equatable {
        case audio
        case data
        case image
        case video
        case button
        case quote
        case call(Bool, String, Int)  // isOutgoing, callState, callDuration
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
            case .video:
                return "video"
            case .button:
                return "button"
            case .quote:
                return "quote"
            case .call:
                return "call"
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
    // Audio/video duration
    var duration: Int?
    // Preview mime type.
    var previewMime: String?
    // Audio/video preview.
    var preview: Data?
    // Reference to preview
    var previewRef: String?
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
        /// Size of the phone icon (video calls).
        static let kCallIconSize: CGFloat = 28
        /// Size of the play/pause icon (square)
        static let kPlayIconSize: CGFloat = 28
        /// Size of the audio wave.
        static let kWaveSize = CGSize(width: 144, height: 32)
        /// URL and Button text color
        static let kLinkColor = UIColor.link //(red: 0, green: 122/255, blue: 1, alpha: 1)
        static let kQuoteTextColorAdj = 0.7 // Adjustment to font alpha in quote to make it less prominent.
        static let kSecondaryColorAlpha = 0.6 // Adjustment to alpha for showing Play/Pause buttons.

        // Successful video call marker (↗, ↙) color.
        static let kSuccessfulCallArrowColor = UIColor(fromHexCode: 0xFF006400)
        static let kFailedCallArrowColor = UIColor.red

        // The base color of the circular background.
        static let kPlayControlBackgroundColor = UIColor(fromHexCode: 0xB0333333)

        /// Video Play button point size.
        static let kVideoPlayButtonPointSize: CGFloat = 60
        /// Video Play button opacity.
        static let kVideoPlayButtonAlpha: CGFloat = 1
        /// Video overlay background opacity.
        static let kVideoOverlayAlpha: CGFloat = 0.7
        /// Video duration text box max width.
        static let kVideoDurationMaxWidth: CGFloat = 50
        /// Video duration text box height.
        static let kVideoDurationHeight: CGFloat = 20
        /// Video duration text box insets.
        static let kVideoDurationInsets = UIEdgeInsets(top: -1, left: -5, bottom: -1, right: -5)
    }

    // Thrown by the formatting function when the length budget gets exceeded.
    // Param represents the maximum prefix fitting within the length budget.
    public enum LengthExceededError: Error {
        case runtimeError(NSAttributedString)
    }

    typealias CharacterStyle = [NSAttributedString.Key: Any]

    private lazy var playIcon: UIImage = {
        let play = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: Constants.kVideoPlayButtonPointSize / 2.6, weight: .bold, scale: .large))!.withTintColor(.white, renderingMode: .alwaysOriginal)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: Constants.kVideoPlayButtonPointSize, height: Constants.kVideoPlayButtonPointSize))
        let img = renderer.image { ctx in
            let bkgColor = Constants.kPlayControlBackgroundColor.cgColor
            ctx.cgContext.setFillColor(bkgColor)
            ctx.cgContext.setStrokeColor(bkgColor)
            ctx.cgContext.setLineWidth(1)

            let rect = CGRect(x: 0, y: 0, width: Constants.kVideoPlayButtonPointSize, height: Constants.kVideoPlayButtonPointSize)
            ctx.cgContext.addEllipse(in: rect)
            ctx.cgContext.drawPath(using: .fillStroke)

            let playSize = play.size
            play.draw(in: CGRect(x: (rect.width - playSize.width) / 2, y: (rect.height - playSize.height) / 2, width: playSize.width, height: playSize.height), blendMode: .luminosity, alpha: CGFloat(Constants.kVideoPlayButtonAlpha))
        }
        return img
    }()

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
        case .video:
            return "{video ref=\(attachment.ref ?? "nil") bits.count=\(attachment.bits?.count ?? -1) \(attachment.name ?? "unnamed") \(attachment.duration ?? 0)ms \(attachment.size ?? 0)B}"
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
        case .call:
            return "{video call}"
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

        let fg = attributes[.foregroundColor] as? UIColor

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
        attributed.append(NSAttributedString(string: fname, attributes: [.font: UIFont(name: "Courier", size: baseFont.pointSize)!, .foregroundColor: fg ?? UIColor.black]))

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
        second.addAttributes([NSAttributedString.Key.paragraphStyle: paragraph, .foregroundColor: fg?.withAlphaComponent(Constants.kSecondaryColorAlpha) ?? UIColor.gray], range: NSRange(location: 0, length: second.length))

        second.endEditing()
        attributed.append(second)

        if isValid {
            // Insert linebreak then a clickable [↓ save] line
            attributed.append(NSAttributedString(string: "\u{2009}\n", attributes: [NSAttributedString.Key.font: baseFont]))

            let second = NSMutableAttributedString(string: "\u{2009}")
            second.beginEditing()

            // Add 'download file' icon
            let icon = NSTextAttachment()
            icon.image = UIImage(systemName: "square.and.arrow.down")?.withRenderingMode(.alwaysTemplate)
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
            attrs[.foregroundColor] = fg.withAlphaComponent(Constants.kSecondaryColorAlpha)
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

    private func createImageAttachmentString(_ attachment: Attachment, maxSize size: CGSize) -> NSAttributedString {
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
    }

    private func createVideoAttachmentString(_ attachment: Attachment, maxSize size: CGSize) -> NSAttributedString {
        let url: URL?
        if let ref = attachment.previewRef {
            url = Utils.tinodeResourceUrl(from: ref)
        } else {
            url = nil
        }

        // Adds Play button and duration overlay on top of img.
        let overlay = { (img: UIImage) -> UIImage? in
            // Input img is the original image which may be scaled upon rendering.
            // Compute the scaling factor and draw properly scaled the play icon and duration label.
            let scaling = UiUtils.sizeUnder(original: img.size, fitUnder: size, scale: 1, clip: false).scale
            let shouldScale = 0 < scaling && scaling < 1

            let rect = CGRect(x: 0, y: 0, width: img.size.width, height: img.size.height)
            let renderer = UIGraphicsImageRenderer(size: img.size)
            let playBtnIcon = self.playIcon

            return renderer.image { ctx in
                var playSize = playBtnIcon.size
                img.draw(in: rect, blendMode: .normal, alpha: 1)
                if shouldScale {
                    playSize.width /= scaling
                    playSize.height /= scaling
                }
                playBtnIcon.draw(in: CGRect(x: (rect.width - playSize.width) / 2, y: (rect.height - playSize.height) / 2, width: playSize.width, height: playSize.height), blendMode: .luminosity, alpha: Constants.kVideoPlayButtonAlpha)

                if let duration = attachment.duration {
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center

                    var font = UIFont.preferredFont(forTextStyle: .caption1)
                    if shouldScale {
                        let fontSize = CGFloat(truncating: font.pointSize / scaling as NSNumber)
                        font = UIFont(descriptor: font.fontDescriptor, size: fontSize)
                    }
                    let attrs = [NSAttributedString.Key.font: font,
                                 NSAttributedString.Key.paragraphStyle: paragraphStyle,
                                 NSAttributedString.Key.foregroundColor: UIColor.white]

                    let durationWidth = shouldScale ? Constants.kVideoDurationMaxWidth / scaling : Constants.kVideoDurationMaxWidth
                    let durationHeight = shouldScale ? Constants.kVideoDurationHeight / scaling : Constants.kVideoDurationHeight
                    let durationRect = CGRect(x: 0, y: rect.height - durationHeight, width: durationWidth, height: durationHeight)

                    // Draw duration string with the gray background.
                    // Have to use layoutManager since NSAttributedString.draw(in: CGRect) does not support background padding & rounded corners.
                    let durationStr = AbstractFormatter.millisToTime(millis: duration, fixedMin: true)
                    let textStorage = NSTextStorage(string: durationStr, attributes: attrs)
                    let textContainer = NSTextContainer(size: durationRect.size)
                    let layoutManager = NSLayoutManager()
                    layoutManager.addTextContainer(textContainer)
                    textStorage.addLayoutManager(layoutManager)

                    let characterRange = NSRange(location: 0, length: durationStr.count)
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
                    let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                    let glyphRange2 = NSRange(0 ..< layoutManager.numberOfGlyphs)
                    let origin = durationRect.origin

                    let bg = boundingRect.offsetBy(dx: origin.x, dy: origin.y).inset(by: Constants.kVideoDurationInsets)

                    UIColor.darkGray.withAlphaComponent(Constants.kVideoOverlayAlpha).set()
                    let path = UIBezierPath(roundedRect: bg, cornerRadius: bg.height * 0.2)
                    path.fill()

                    layoutManager.drawGlyphs(forGlyphRange: glyphRange2, at: origin)
                }
            }
        }

        // tinode:// and mid: schemes are not real external URLs.
        let wrapper = (url == nil || url!.scheme == "mid" || url!.scheme == "tinode") ? EntityTextAttachment() : AsyncImageTextAttachment(url: url!, afterDownloaded: { (img: UIImage) -> UIImage? in
            var im: UIImage?
            if let done = attachment.afterRefDownloaded {
                im = done(img)
            } else {
                im = img
            }
            if let postImg = im {
                return overlay(postImg)
            }
            return im
        })
        wrapper.type = "video"
        wrapper.draftyEntityKey = attachment.draftyEntityKey

        var preview: UIImage?
        if let previewBits = attachment.preview, let previewImage = UIImage(data: previewBits) {
            preview = previewImage
        }

        var originalSize: CGSize
        if let width = attachment.width, let height = attachment.height, width > 0 && height > 0 {
            // Sender provider valid width and height of the image.
            originalSize = CGSize(width: width, height: height)
        } else if let preview = preview {
            originalSize = preview.size
        } else {
            originalSize = CGSize(width: UiUtils.kDefaultBitmapSize, height: UiUtils.kDefaultBitmapSize)
        }

        let scaledSize = UiUtils.sizeUnder(original: originalSize, fitUnder: size, scale: 1, clip: false).dst
        if preview == nil {
            if attachment.previewRef != nil {
                // No need to scale the stock image.
                wrapper.image = UiUtils.placeholderImage(named: "image-wait", withBackground: nil, width: scaledSize.width, height: scaledSize.height)
            } else {
                // No preview poster? Display controls over the gray background image.
                wrapper.image = overlay(UIColor.gray.image(scaledSize))
            }
        } else {
            wrapper.image = overlay(preview!)
        }
        wrapper.bounds = CGRect(origin: attachment.offset ?? .zero, size: scaledSize)

        (wrapper as? AsyncImageTextAttachment)?.startDownload(onError: overlay(UIColor.gray.image(scaledSize))!)

        return NSAttributedString(attachment: wrapper)
    }

    private func createVideoCallAttachmentString(isOutgoing: Bool, callState: String, callDuration: Int,
                                                 defaultAttrs attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: "\u{2009}")
        attributed.beginEditing()

        // Large phone icon.
        let icon = NSTextAttachment()
        icon.image = UIImage(systemName: "phone")?.withRenderingMode(.alwaysTemplate)
        var aspectRatio: CGFloat = 1
        if let size = icon.image?.size {
            aspectRatio = size.width / size.height
        }
        let baseFont = attributes[.font] as! UIFont
        icon.bounds = CGRect(origin: CGPoint(x: 0, y: baseFont.capHeight - Constants.kCallIconSize), size: CGSize(width: Constants.kCallIconSize * aspectRatio, height: Constants.kCallIconSize))

        attributed.append(NSAttributedString(attachment: icon))
        attributed.addAttributes(attributes, range: NSRange(location: 0, length: attributed.length))
        attributed.append(NSAttributedString(string: " "))

        attributed.append(NSAttributedString(string: isOutgoing ? NSLocalizedString("Outgoing call", comment: "Label for outgoing video/audio calls") : NSLocalizedString("Incoming call", comment: "Label for incoming video/audio calls"), attributes: attributes))

        // Linebreak.
        attributed.append(NSAttributedString(string: "\u{2009}\n", attributes: [NSAttributedString.Key.font: baseFont]))

        // Second line: call status and duration.
        let arrow = NSMutableAttributedString()
        arrow.beginEditing()

        let success = ![MsgServerData.WebRTC.kBusy.rawValue, MsgServerData.WebRTC.kDisconnected.rawValue, MsgServerData.WebRTC.kMissed.rawValue, MsgServerData.WebRTC.kDeclined.rawValue].contains(callState)
        let arrowIcon = NSTextAttachment()
        arrowIcon.image = AbstractFormatter.callStatusIcon(incoming: !isOutgoing, success: success)
        aspectRatio = 1
        if let size = arrowIcon.image?.size {
            aspectRatio = size.width / size.height
        }
        arrowIcon.bounds = CGRect(origin: CGPoint(x: 0, y: -2), size: CGSize(width: baseFont.lineHeight * 0.7 * aspectRatio, height: baseFont.lineHeight * 0.7))
        arrow.append(NSAttributedString(attachment: arrowIcon))
        arrow.addAttribute(.foregroundColor, value: success ? Constants.kSuccessfulCallArrowColor : Constants.kFailedCallArrowColor, range: NSRange(location: 0, length: arrow.length))

        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = Constants.kCallIconSize + baseFont.capHeight * 0.25
        paragraph.lineSpacing = 0
        paragraph.lineHeightMultiple = 0.5
        arrow.addAttributes([NSAttributedString.Key.paragraphStyle: paragraph], range: NSRange(location: 0, length: arrow.length))

        arrow.append(NSAttributedString(string: " "))
        if callDuration > 0 {
            arrow.append(NSAttributedString(string: AbstractFormatter.millisToTime(millis: callDuration), attributes: attributes))
        } else {
            arrow.append(NSAttributedString(string: AbstractFormatter.callStatusText(incoming: !isOutgoing, event: callState), attributes: attributes))
        }

        arrow.addAttribute(.font, value: baseFont.withSize(baseFont.pointSize * 0.9), range: NSRange(location: 0, length: arrow.length))

        arrow.endEditing()
        attributed.append(arrow)

        attributed.endEditing()
        return attributed
    }

    private func composeBody(defaultText: String, defaultAttrs attributes: [NSAttributedString.Key: Any], fontTraits: UIFontDescriptor.SymbolicTraits?, maxSize size: CGSize) -> NSAttributedString {
        let body = NSMutableAttributedString()
        body.beginEditing()

        if let text = text {
            body.append(FormatNode.textToAttributed(text, defaultAttrs: attributes, fontTraits: fontTraits))
        } else if let children = children {
            for child in children {
                body.append(try! child.toAttributed(withAttributes: attributes, fontTraits: fontTraits, fitIn: size))
            }
        } else {
            body.append(NSAttributedString(string: defaultText, attributes: attributes))
        }

        body.endEditing()
        return body
    }

    /// Create custom layout for attachments.
    private func attachmentToAttributed(_ attachment: Attachment, defaultAttrs attributes: [NSAttributedString.Key: Any], fontTraits: UIFontDescriptor.SymbolicTraits?, maxSize size: CGSize) -> NSAttributedString {
        switch attachment.content {

        case .audio:
            return createAudioAttachmentString(attachment, withData: attachment.bits, withRef: attachment.ref, defaultAttrs: attributes, maxSize: size)
        case .image:
            return createImageAttachmentString(attachment, maxSize: size)
        case .video:
            return createVideoAttachmentString(attachment, maxSize: size)
        case .button:
            // Change color of text from default to link color.
            var attrs = attributes
            attrs[.foregroundColor] = Constants.kLinkColor
            let entity = NSLocalizedString("button", comment: "Text written on button face when all else fails.")
            let faceText = composeBody(defaultText: entity, defaultAttrs: attrs, fontTraits: fontTraits, maxSize: size)
            return NSAttributedString(attachment: ButtonAttachment(face: faceText, data: URL(string: attachment.ref!)))

        case .quote:
            let faceText = composeBody(defaultText: " ", defaultAttrs: attributes, fontTraits: fontTraits, maxSize: size)
            return NSAttributedString(attachment: QuotedAttachment(quotedText: faceText, fitIn: size, fullWidth: attachment.fullWidth ?? false))

        case .call(let isOutgoing, let callState, let callDuration):
            return createVideoCallAttachmentString(isOutgoing: isOutgoing, callState: callState, callDuration: callDuration, defaultAttrs: attributes)

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

            attributed.append(composeBody(defaultText: NSLocalizedString("Unsupported", comment: "Unsupported (unknown) Drafty tag"), defaultAttrs: attributes, fontTraits: fontTraits, maxSize: size))

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
