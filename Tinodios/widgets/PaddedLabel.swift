//
//  PaddedLabel.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

public class PaddedLabel: UILabel {
    @IBInspectable var topInset: CGFloat = 0.0 {
        didSet { updateInsets() }
    }
    @IBInspectable var bottomInset: CGFloat = 0.0 {
        didSet { updateInsets() }
    }
    @IBInspectable var leftInset: CGFloat = 0.0 {
        didSet { updateInsets() }
    }
    @IBInspectable var rightInset: CGFloat = 0.0 {
        didSet { updateInsets() }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        updateInsets()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        updateInsets()
    }

    private func updateInsets() {
        textInsets = UIEdgeInsets(top: topInset, left: leftInset, bottom: bottomInset, right: rightInset)
    }

    public var textInsets: UIEdgeInsets = .zero {
        didSet { setNeedsDisplay() }
    }

    override public func drawText(in rect: CGRect) {
        let insetRect = rect.inset(by: textInsets)
        super.drawText(in: insetRect)
    }
}
