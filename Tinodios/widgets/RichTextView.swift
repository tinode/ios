//
//  RichTextLabel.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

/// UITextView with some layout issues fixed.
class RichTextView : UITextView {

    override func layoutSubviews() {
        super.layoutSubviews()
        setup()
    }

    func setup() {
        // Apple is a steaming pile of buggy $#14
        // See https://stackoverflow.com/questions/746670/how-to-lose-margin-padding-in-uitextview
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        contentInset = UIEdgeInsets.zero

        isScrollEnabled = false
        isUserInteractionEnabled = true
        isEditable = false
        isSelectable = true

        var b = bounds
        b.size.height = sizeThatFits(CGSize(width: bounds.size.width, height: CGFloat.greatestFiniteMagnitude)).height
        bounds = b
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(contentOffset, animated: false)
    }

    // MARK: public methods

    public func getURLForTap(_ location: CGPoint) -> URL? {
        // See discussion: https://stackoverflow.com/questions/19318092/how-to-detect-touch-on-nstextattachment/49153247#49153247

        let glyphIndex: Int = layoutManager.glyphIndex(for: location, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

        guard glyphRect.contains(location) else { return nil }

        let characterIndex: Int = layoutManager.characterIndexForGlyph(at: glyphIndex)

        guard characterIndex < textStorage.length else { return nil }

        // Check if an URL was tapped
        if let link = textStorage.attribute(.link, at: characterIndex, effectiveRange: nil) as? NSURL {
            return link.absoluteURL
        }

        guard NSTextAttachment.character == (textStorage.string as NSString).character(at: characterIndex) else { return nil }
        guard let attachment = textStorage.attribute(.attachment, at: characterIndex, effectiveRange: nil) as? NSTextAttachment else { return nil }

        if let button = attachment as? DraftyButtonAttachment {
            return button.payload
        }

        if attachment.image != nil {
            return URL(string: "tinode:///preview-image")
        }

        return URL(string: "tinode:///generic-attachment")
    }
}
