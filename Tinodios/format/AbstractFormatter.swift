//
//  AbstractFormatter.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK


/// DraftyFormatter implementation to break out individual format handlers.
/// Implemented as a class instead of a protocol because of this bug: https://bugs.swift.org/browse/SR-103
class AbstractFormatter: DraftyFormatter {
    let defaultAttrs: [NSAttributedString.Key: Any]

    init(defaultAttributes attrs: [NSAttributedString.Key: Any], defaultFont: UIFont) {
        var attributes = attrs
        if attributes[.font] == nil {
            attributes[.font] = defaultFont
        }
        defaultAttrs = attributes
    }

    func handlePlain(_ nodes: [FormatNode]) -> FormatNode {
        return FormatNode(nodes)
    }

    func handleLineBreak() -> FormatNode {
        return FormatNode()
    }
    func handleAttachment(using: [String : JSONValue]?, draftyKey: Int?) -> FormatNode {
        return FormatNode()
    }
    func handleHidden() -> FormatNode {
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

    func handleLink(content: [FormatNode], using: [String : JSONValue]?) -> FormatNode {
        return FormatNode()
    }

    func handleMention(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        return FormatNode()
    }

    func handleHashtag(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        // TODO: add support for #hashtangs
        return FormatNode(nodes)
    }

    func handleAudio(using: [String : JSONValue]?, draftyKey: Int?) -> FormatNode {
        return FormatNode()
    }

    func handleImage(using: [String : JSONValue]?, draftyKey: Int?) -> FormatNode {
        return FormatNode()
    }

    func handleButton(content: [FormatNode], using: [String : JSONValue]?) -> FormatNode {
        return FormatNode()
    }

    func handleForm(_: [FormatNode]) -> FormatNode {
        return FormatNode()
    }

    func handleFormRow(_: [FormatNode]) -> FormatNode {
        return FormatNode()
    }

    func handleQuote(_: [FormatNode]) -> FormatNode {
        return FormatNode()
    }

    func handleUnknown(content: [FormatNode], using: [String : JSONValue]?, draftyKey: Int?) -> FormatNode {
        return FormatNode()
    }

    public func wrapText(_ content: String) -> FormattedString {
        return FormatNode(content)
    }

    public func apply(type: String?, data: [String : JSONValue]?, key: Int?, content: [FormattedString], stack: [String]?) -> FormattedString {
        let children = content as? [FormatNode]

        if Drafty.isVoid(type: type) {
            switch type {
            case "BR":
                return handleLineBreak()
            case "EX":
                return handleAttachment(using: data, draftyKey: key)
            case "HD":
                return FormatNode()
            default:
                return FormatNode()
            }
        } else if let children = children {
            switch type {
            case nil, "":
                return handlePlain(children)
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
            case "AU":
                return handleAudio(using: data, draftyKey: key)
            case "IM":
                return handleImage(using: data, draftyKey: key)
            case "BN":
                return handleButton(content: children, using: data)
            case "FM":
                return handleForm(children)
            case "RW":
                return handleFormRow(children)
            case "QQ":
                return handleQuote(children)
            default:
                return handleUnknown(content: children, using: data, draftyKey: key)
            }
        }
        // Non-void and no children (invalid).
        return FormatNode()
    }

    /// Convert drafty object into NSAttributedString
    /// - Parameters:
    ///    - content: Drafty object to convert
    ///    - fitIn: maximum size of attached images.
    public func toAttributed(_ content: Drafty, fitIn maxSize: CGSize, attributes: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString {
        // Merge custom attributes with default using custom in case of a conflict.
        let allAttribs = self.defaultAttrs.merging(attributes ?? [:]) { $1 }

        if content.isPlain {
            return NSMutableAttributedString(string: content.string, attributes: allAttribs)
        }

        let formatTree: FormatNode = content.format(formatWith: self, resultType: FormatNode.self) ?? FormatNode()
        return (try? formatTree.toAttributed(withAttributes: allAttribs, fontTraits: nil, fitIn: maxSize)) ?? NSAttributedString()
    }

    // Convert milliseconds to '00:00' format.
    static func millisToTime(millis: Int, fixedMin: Bool = false) -> String {
        var result = ""
        let duration: Float = Float(millis) / 1000.0
        let mins = floor(duration / 60)
        if (fixedMin && mins < 10) {
            result.append("0")
        }
        result.append("\(Int(mins)):")
        let sec = duration.truncatingRemainder(dividingBy: 60)
        if sec < 10 {
            result.append("0")
        }
        result.append("\(Int(sec))")
        return result
    }
}
