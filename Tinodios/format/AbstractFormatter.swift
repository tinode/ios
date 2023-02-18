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

    func handleVideoCall(content: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        return FormatNode()
    }

    func handleVideo(using: [String : JSONValue]?, draftyKey: Int?) -> FormatNode {
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
            case "VC":
                return handleVideoCall(content: children, using: data)
            case "VD":
                return handleVideo(using: data, draftyKey: key)
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
    public func toAttributed(_ content: Drafty, fitIn maxSize: CGSize) -> NSAttributedString {
        if content.isPlain {
            return NSMutableAttributedString(string: content.string, attributes: self.defaultAttrs)
        }

        let formatTree: FormatNode = content.format(formatWith: self, resultType: FormatNode.self) ?? FormatNode()
        return (try? formatTree.toAttributed(withAttributes: self.defaultAttrs, fontTraits: nil, fitIn: maxSize)) ?? NSAttributedString()
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

    static func callStatusText(incoming: Bool, event: String) -> String {
        var comment: String
        switch event {
        case MsgServerData.WebRTC.kBusy.rawValue:
            comment = NSLocalizedString(MsgServerData.WebRTC.kBusy.rawValue, comment: "Label for declined call due to line being busy")
        case MsgServerData.WebRTC.kDeclined.rawValue:
            comment = NSLocalizedString(MsgServerData.WebRTC.kDeclined.rawValue, comment: "Label for declined call")
        case MsgServerData.WebRTC.kMissed.rawValue:
            comment = incoming ?
                NSLocalizedString(MsgServerData.WebRTC.kMissed.rawValue, comment: "Label for missed call") :
                NSLocalizedString("cancelled", comment: "Label for cancelled call")
        case MsgServerData.WebRTC.kStarted.rawValue:
            comment = NSLocalizedString("connecting", comment: "Label for initiated call")
        case MsgServerData.WebRTC.kAccepted.rawValue:
            comment = NSLocalizedString("in progress", comment: "Label for call in progress")
        default:
            comment = NSLocalizedString(MsgServerData.WebRTC.kDisconnected.rawValue, comment: "Label for disconnected call")
        }
        return comment
    }

    static func callStatusIcon(incoming: Bool, success: Bool) -> UIImage? {
        return (success ? UIImage(systemName: incoming ? "arrow.down.left" : "arrow.up.right") : incoming ? UIImage(systemName: "arrow.uturn.up")?.withHorizontallyFlippedOrientation() : UIImage(systemName: "arrow.uturn.up"))?.withRenderingMode(.alwaysTemplate)
    }
}
