//
//  RichTextLabel.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

extension NSAttributedString.Key {
    static let drafyButton = NSAttributedString.Key(rawValue: "DraftyButton")
}

class DraftyLayoutManager: NSLayoutManager {

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        let range = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        self.textStorage?.enumerateAttribute(NSAttributedString.Key.drafyButton, in: range,  using: { (value, range, stop) in
            if value != nil {
                let color: UIColor = value as! UIColor

                let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let container = self.textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil)

                // draw background
                let context = UIGraphicsGetCurrentContext();
                context!.saveGState()
                context!.translateBy(x: origin.x, y: origin.y)
                context!.setFillColor(color.cgColor)
                let rect = self.boundingRect(forGlyphRange: glyphRange, in: container!)

                // UIBezierPath with rounded corners
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 18)
                path.fill()
                context!.restoreGState()
            }
        })
    }

}

// UITextView with custom layout. Used for displaying message content.
// Custom layout is used for drawing Drafty forms and detecting clicks.
class RichTextLabel : UITextView {

    override func layoutSubviews() {
        super.layoutSubviews()
        setup()
    }

    func setup() {
        // See https://stackoverflow.com/questions/746670/how-to-lose-margin-padding-in-uitextview
        textContainerInset = UIEdgeInsets.zero
        textContainer.lineFragmentPadding = 0
    }

    // MARK: public methods

    public func getURLForTap(_ location: CGPoint) -> URL? {
        return nil
    }
}
