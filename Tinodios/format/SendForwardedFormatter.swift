//
//  SendForwardedFormatter.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import UIKit

// Formatter for displaying forwarded previews before they are sent.
class SendForwardedFormatter: QuoteFormatter {
    override func apply(type: String?, data: [String : JSONValue]?, key: Int?, content: [FormattedString], stack: [String]?) -> FormattedString {
        if let stack = stack, stack.contains("QQ") {
            if let type = type, type == "QQ" {
                // Quote inside quote, convert to icon.
                return self.handleQuoteInsideQuote([])
            }
        }
        return super.apply(type: type, data: data, key: key, content: content, stack: stack)
    }

    func handleQuoteInsideQuote(_ nodes: [FormatNode]) -> FormatNode {
        return FormatNode([annotatedIcon(iconName: "text.quote"), FormatNode(" ")])
    }

    override func handleQuote(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        node.attachment(Attachment(content: .quote, fullWidth: true))
        return node
    }
}
