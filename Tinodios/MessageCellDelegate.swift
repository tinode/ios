//
//  MessageCellDelegate.swift
//  Tinodios
//
//  Created by Gene Sokolov on 03/05/2019.
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

/// A protocol used to detect taps in the chat message.
public protocol MessageCellDelegate {

    func didTapMessage(in cell: MessageCell)
}

public extension MessageCellDelegate {
    func didTapMessage(in cell: MessageCell) {}
}
