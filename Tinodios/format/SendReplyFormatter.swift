//
//  SendReplyFormatter.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import UIKit

// TODO: remove?
class SendReplyFormatter: QuoteFormatter {
    static let kQuotedReplyLength = 64

    override func handleQuote(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        node.attachment(Attachment(content: .quote, fullWidth: true))
        return node
    }
}
