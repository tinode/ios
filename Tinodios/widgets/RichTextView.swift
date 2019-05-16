//
//  RichTextLabel.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

extension NSAttributedString.Key {
    static let draftyButton = NSAttributedString.Key(rawValue: "draftyButton")
}

class DraftyTextContainer : NSTextContainer {

    override var isSimpleRectangularTextContainer: Bool { return false }

    // This is needed for giving buttons more space.
    override func lineFragmentRect(forProposedRect proposedRect: CGRect, at characterIndex: Int, writingDirection baseWritingDirection: NSWritingDirection, remaining remainingRect: UnsafeMutablePointer<CGRect>?) -> CGRect {

        var rect = super.lineFragmentRect(forProposedRect: proposedRect, at: characterIndex, writingDirection: baseWritingDirection, remaining: remainingRect)

        if let textStorage = layoutManager?.textStorage, textStorage.length > 0 {
            let range = NSRange(location: characterIndex, length: textStorage.length - characterIndex)
            textStorage.enumerateAttribute(.draftyButton, in: range, options: .longestEffectiveRangeNotRequired) { (value, range, stop) in
                if value != nil {
                    let str = textStorage.attributedSubstring(from: range)
                    // rect.origin.x += 10
                    // rect.size.width += 20
                    print("Drafty button at \(characterIndex)->\(range) '\(str.string)' rect=\(rect)  remainder=\(remainingRect?.pointee ?? .zero)")
                }
            }
        }
        return rect
    }
}

class DraftyLayoutManager : NSLayoutManager {

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        let range = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage?.enumerateAttribute(.draftyButton, in: range, using: { (value, range, stop) in
            guard let color = value as? UIColor else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let container = self.textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil)

            // Draw background around buttons.
            if let context = UIGraphicsGetCurrentContext() {
                context.saveGState()
                context.translateBy(x: origin.x, y: origin.y)
                context.setFillColor(color.cgColor)
                var rect = boundingRect(forGlyphRange: glyphRange, in: container!)
                // rect.size.width += 20
                // UIBezierPath with rounded corners
                let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.size.height * 0.5)
                path.fill()
                context.restoreGState()
            }
        })
    }
/*
    override func lineFragmentRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?, withoutAdditionalLayout flag: Bool) -> CGRect {
        var rect = super.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: effectiveGlyphRange, withoutAdditionalLayout: flag)

        let range = self.characterRange(forGlyphRange: glyphIndex, actualGlyphRange: effectiveGlyphRange)
        self.textStorage?.enumerateAttribute(.draftyButton, in: range, using: { (value, range, stop) in
            guard let color = value as? UIColor else { return }


        })
        return rect
    }
*/
}

// UITextView with custom layout. Used for displaying message content.
// Custom layout is used for drawing Drafty forms and detecting clicks.
class RichTextView : UITextView {

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    convenience init() {
        let textStorage = NSTextStorage()
        let layoutManager = DraftyLayoutManager()
        let textContainer = DraftyTextContainer(size: .zero)

        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        self.init(frame: .zero, textContainer: textContainer)
    }

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
