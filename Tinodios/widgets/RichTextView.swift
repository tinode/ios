//
//  RichTextLabel.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

// UITextView with some layout issues fixed.
class RichTextView : UITextView {

    override func layoutSubviews() {
        super.layoutSubviews()
        setup()
    }

    func setup() {
        // Apple is a steaming pile of buggy $#14
        // See https://stackoverflow.com/questions/746670/how-to-lose-margin-padding-in-uitextview
        textContainerInset = .zero //UIEdgeInsets(top: 6, left: 0, bottom: 4, right: 0)
        textContainer.lineFragmentPadding = 0
        contentInset = UIEdgeInsets.zero
        isScrollEnabled = false

        var b = bounds
        let h = sizeThatFits(CGSize(
            width: bounds.size.width,
            height: CGFloat.greatestFiniteMagnitude)
            ).height
        b.size.height = h
        bounds = b
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(contentOffset, animated: false)
    }

    // MARK: public methods

    public func getURLForTap(_ location: CGPoint) -> URL? {
        return nil
    }
}
