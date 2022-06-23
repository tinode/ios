//
//  PaddedLabel.swift
//  Tinodios
//
//  Copyright © 2019-2022 Tinode. All rights reserved.
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
    @IBInspectable var cornerRadius: CGFloat = 0.0 {
        didSet { updateCornerRadius() }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        updateInsets()
        updateCornerRadius()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        updateInsets()
        updateCornerRadius()
    }

    private func updateInsets() {
        textInsets = UIEdgeInsets(top: topInset, left: leftInset, bottom: bottomInset, right: rightInset)
    }

    private func updateCornerRadius() {
        layer.masksToBounds = true
        clipsToBounds = true
        layer.cornerRadius = cornerRadius
    }

    public var textInsets: UIEdgeInsets = .zero {
        didSet { setNeedsDisplay() }
    }

    override public var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + leftInset + rightInset, height: size.height + topInset + bottomInset)
    }

    override public func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override public var bounds: CGRect {
        didSet {
            // ensures this works within stack views if multi-line
            preferredMaxLayoutWidth = bounds.width - (leftInset + rightInset)
        }
    }
}
