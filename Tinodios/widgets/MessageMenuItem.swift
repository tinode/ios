//
//  MessageMenuItem.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit


class MessageMenuItem: UIMenuItem {
    var seqId: Int = -1

    init(title: String, action: Selector, seqId: Int) {
        super.init(title: title, action: action)
        self.seqId = seqId
    }
}
