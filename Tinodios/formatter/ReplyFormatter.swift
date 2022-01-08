//
//  ReplyFormatter.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import UIKit

class ReplyFormatter: AttributedStringFormatter {
    override func handleQuote(_ nodes: [FormatNode]) -> FormatNode {
        return handleQuoteImpl(nodes)
    }
}
