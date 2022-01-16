//
//  AttributedStringFormatter.swift
//  Tinodios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//
//  Converts Drafty instance into attributed text suitable for display in UITextView

import TinodeSDK
import UIKit

// iOS's support for styled strings is much weaker than Android's and web. Some styles cannot be nested. They have to be constructed and applied all at once at the leaf level.

/// Class which creates NSAttributedString with Drafty format applied.
class AttributedStringFormatter: DraftyFormatter {
    internal enum Constants {
        static let kDefaultFont: UIFont = UIFont.preferredFont(forTextStyle: .body)
    }

    let defaultAttrs: [NSAttributedString.Key: Any]

    required init(withDefaultAttributes attrs: [NSAttributedString.Key: Any]) {
        defaultAttrs = attrs
    }

    func wrapText(_ content: String) -> FormattedString {
        return FormatNode(content)
    }

    func apply(type: String?, data: [String : JSONValue]?, key: Int?, content: [FormattedString], stack: [String]?) -> FormattedString {
        let children = content as? [FormatNode]

        guard let type = type else {
            return handlePlain(children)
        }
        if Drafty.isVoid(type: type) {
            switch type {
            case "BR":
                return handleLineBreak()
            case "EX":
                return handleAttachment(using: data)
            case "HD":
                return FormatNode()
            default:
                return FormatNode()
            }
        } else if let children = children {
            switch type {
            case "ST":
                return handleStrong(children)
            case "EM":
                return handleEmphasized(children)
            case "DL":
                return handleDeleted(children)
            case "CO":
                return handleCode(children)
            case "LN":
                return handleLink(content: children, using: data)
            case "MN":
                return handleMention(content: children, using: data)
            case "HT":
                return handleHashtag(content: children, using: data)
            case "IM":
                return handleImage(using: data, fromDraftyEntity: key)
            case "BN":
                return handleButton(content: children, using: data)
            case "FM":
                return handleForm(children)
            case "RW":
                return handleFormRow(children)
            case "QQ":
                return handleQuote(children)
            default:
                return handleUnknown(children)
            }
        }
        // Non-void and no children (invalid).
        return FormatNode()
    }

    func handleStrong(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        node.style(fontTraits: .traitBold)
        return node
    }

    func handleEmphasized(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        node.style(fontTraits: .traitItalic)
        return node
    }

    func handleDeleted(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        node.style(cstyle: [NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.single.rawValue])
        return node
    }

    func handleCode(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        // .traitMonoSpace is not a real font trait. It cannot be applied to an arbitrary font. A real
        // monospaced font must be selected manually.
        let baseFont = defaultAttrs[.font] as! UIFont
        var attributes = defaultAttrs
        attributes[.font] = UIFont(name: "Courier", size: baseFont.pointSize)!
        node.style(cstyle: attributes)
        return node
    }

    func handleHidden() -> FormatNode {
        return FormatNode()
    }

    func handleLineBreak() -> FormatNode {
        return FormatNode("\n")
    }

    func handleLink(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        let node = FormatNode(nodes)
        if let urlString = data?["url"]?.asString(), let url = NSURL(string: urlString), url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" {
            node.style(cstyle: [NSAttributedString.Key.link: url])
        }
        return node
    }

    func handleMention(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        let node = FormatNode(nodes)
        if let uid = data?["val"]?.asString() {
            node.style(cstyle: [.foregroundColor: UiUtils.letterTileColor(for: uid, dark: true)])
        }
        return node
    }

    func handleHashtag(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        // TODO: add support for #hashtangs
        return FormatNode(nodes)
    }

    func handleImage(using data: [String: JSONValue]?, fromDraftyEntity key: Int?) -> FormatNode {
        var attachment = Attachment(content: .image)
        let node = FormatNode()
        if let attr = data {
            attachment.bits = attr["val"]?.asData()
            attachment.mime = attr["mime"]?.asString()
            attachment.name = attr["name"]?.asString()
            attachment.ref = attr["ref"]?.asString()
            attachment.size = attr["size"]?.asInt()
            attachment.width = attr["width"]?.asInt()
            attachment.height = attr["height"]?.asInt()
        }
        attachment.draftyEntityKey = key
        node.attachment(attachment)
        return node
    }

    func handleAttachment(using data: [String: JSONValue]?) -> FormatNode {
        let node = FormatNode()
        if let attr = data {
            let mimeType =  attr["mime"]?.asString()

            // Skip json attachments. They are not meant to be user-visible.
            if mimeType == "application/json" {
                return node
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
            return node
        }

        // Invalid attachment.
        node.attachment(Attachment(content: .empty))
        return node
    }

    func handleButton(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        let node = FormatNode(nodes)
        guard let urlStr = AttributedStringFormatter.buttonDataAsUri(face: node, attr: data), let url = URL(string: urlStr) else { return node }

        let attachment = Attachment(content: .button, ref: url.absoluteString)
        node.attachment(attachment)
        return node
    }

    func handleForm(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        if var children = node.children, !children.isEmpty {
            // Add line breaks between form elements: each direct descendant is a paragraph.
            for i in stride(from: children.count-1, to: 0, by: -1) {
                children.insert(FormatNode("\n"), at: i)
            }
            node.children = children
        }
        return node
    }

    func handleFormRow(_ nodes: [FormatNode]) -> FormatNode {
        // Form element formatting is dependent on element content.
        // No additional handling is needed.
        return FormatNode(nodes)
    }

    func handleUnknown(_ nodes: [FormatNode]) -> FormatNode {
        // Unknown formatting, treat as plain text
        return FormatNode(nodes)
    }

    func handlePlain(_ nodes: [FormatNode]?) -> FormatNode {
        guard let nodes = nodes else { return FormatNode() }
        return FormatNode(nodes)
    }

    internal func handleQuoteImpl(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        let attachment = Attachment(content: .quote)
        node.attachment(attachment)
        return node
    }

    func handleQuote(_ nodes: [FormatNode]) -> FormatNode {
        let node = handleQuoteImpl(nodes)
        let outer = FormatNode([node, FormatNode("\n")])
        return outer
    }

    // Convert button payload to an URL.
    // NSAttributedString.Key.link wants payload to be NSURL.
    internal static func buttonDataAsUri(face: FormatNode, attr: [String: JSONValue]?) -> String? {
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

    /// Convert drafty object into NSAttributedString
    /// - Parameters:
    ///    - content: Drafty object to convert
    ///    - fitIn: maximum size of attached images.
    ///    - defaultAttrs: default attribues to apply to all otherwise unstyled content.
    ///    - textColor: default text color.
    public class func toAttributed(_ content: Drafty, fitIn maxSize: CGSize, withDefaultAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString {

        var attributes: [NSAttributedString.Key: Any] = attributes ?? [:]
        if attributes[.font] == nil {
            attributes[.font] = Constants.kDefaultFont
        }

        if content.isPlain {
            return NSMutableAttributedString(string: content.string, attributes: attributes)
        }

        let formatTree: FormatNode = content.format(formatWith: AttributedStringFormatter(withDefaultAttributes: attributes), resultType: FormatNode.self) ?? FormatNode()
        return (try? formatTree.toAttributed(withDefaultAttributes: attributes, fontTraits: nil, fitIn: maxSize)) ?? NSAttributedString()
    }
}
