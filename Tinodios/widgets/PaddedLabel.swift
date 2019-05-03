//
//  PaddedLabel.swift
//  Tinodios
//
//  Created by Gene Sokolov on 03/05/2019.
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

public class PaddedLabel: UILabel {

    public var textInsets: UIEdgeInsets = .zero {
        didSet { setNeedsDisplay() }
    }

    override public func drawText(in rect: CGRect) {
        let insetRect = rect.inset(by: textInsets)
        super.drawText(in: insetRect)
    }
}

