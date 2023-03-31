//
//  PinnedMessagesView.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import UIKit

class PinnedMessagesView: UIView {
    private static let kCornerRadius:CGFloat = 20

    public var pins: [Int] = [] {
        didSet {

        }
    }

    public var selected: Int = 0 {
        didSet {

        }
    }
}
