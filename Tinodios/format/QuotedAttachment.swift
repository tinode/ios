//
//  QuotedAttachment.swift
//  Tinodios
//
//  Copyright © 2021-2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK

// An NSTextAttachment which renders quoted Drafty document.
class QuotedAttachment: NSTextAttachment {
    private enum Constants {
        // Mimumum quote width in points
        static let kMinWidth: CGFloat = 40
        // Quote width padding in characters.
        static let kWidthPadding: CGFloat = 2
        // Offset of the text from the top left corner.
        static let kVerticalTextOffset: CGFloat = 4
        static let kHorizontalTextOffset: CGFloat = 6
        static let kQuoteBackgroundColor = UIColor(fromHexCode: 0x18000000)
        static let kStripeColor = UIColor.link
        static let kQuoteCornerRadius: CGFloat = 3.5
    }

    var attributedString: NSAttributedString

    let widthPadding: CGFloat
    let backgroundColor: UIColor
    let stripeColor: UIColor

    init(quotedText: NSAttributedString, fitIn maxSize: CGSize, widthPadding: CGFloat = Constants.kWidthPadding, verticalOffset: CGFloat = 0, fullWidth: Bool = false) {
        attributedString = quotedText
        self.widthPadding = widthPadding
        self.backgroundColor = Constants.kQuoteBackgroundColor
        self.stripeColor = Constants.kStripeColor
        super.init(data: nil, ofType: "public.text")

        let textSize = TextSizeHelper().computeSize(for: quotedText, within: maxSize.width - Constants.kHorizontalTextOffset * 2)
        let absolutePosition = quotedText.boundingRect(with: maxSize, context: nil)

        let textBounds = CGRect(origin: absolutePosition.origin, size: textSize)

        // Calculate quote width: string width + some characters extra, but no less than kMinWidth
        let width: CGFloat
        if fullWidth {
            width = maxSize.width - Constants.kHorizontalTextOffset * 2
        } else {
            width = max(Constants.kMinWidth, textBounds.width / CGFloat(quotedText.length) * (CGFloat(quotedText.length) + self.widthPadding))
        }

        image = renderQuote(textBounds: textBounds, quoteBounds: CGRect(x: 0, y: 0, width: width, height: textBounds.height + Constants.kVerticalTextOffset * 2))
        bounds = CGRect(x: 0, y: verticalOffset, width: width, height: textBounds.height + Constants.kVerticalTextOffset * 2)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Quote as an image.
    private func renderQuote(textBounds: CGRect, quoteBounds: CGRect) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: quoteBounds.width, height: quoteBounds.height), false, UIScreen.main.scale)

        defer { UIGraphicsEndImageContext() }
        let context = UIGraphicsGetCurrentContext()!

        context.saveGState()
        context.clip(to: quoteBounds)

        // Background rectangle with rounded corners: UIBezierPath.
        let bkgRect = quoteBounds.insetBy(dx: 1, dy: 1)

        // Draw background.
        context.setFillColor(self.backgroundColor.cgColor)
        //context.setBlendMode(.multiply)
        UIBezierPath(roundedRect: bkgRect, cornerRadius: Constants.kQuoteCornerRadius).fill()
        //context.setBlendMode(.normal)

        // Draw the stripe on the left of the quote box.
        let stripe = UIBezierPath()
        let start = CGPoint(x: bkgRect.minX + Constants.kQuoteCornerRadius, y: bkgRect.minY + Constants.kQuoteCornerRadius)
        // Top rounded corner.
        stripe.addArc(withCenter: start, radius: Constants.kQuoteCornerRadius * 0.5, startAngle: 1.5 * CGFloat.pi, endAngle: CGFloat.pi, clockwise: false)
        // Vertical stripe body.
        stripe.move(to: CGPoint(x: bkgRect.minX + Constants.kQuoteCornerRadius * 0.5, y: bkgRect.minY + Constants.kQuoteCornerRadius))
        let dest = CGPoint(x: bkgRect.minX + Constants.kQuoteCornerRadius * 0.5, y: bkgRect.maxY - Constants.kQuoteCornerRadius)
        stripe.addLine(to: dest)
        // Rounded corner.
        let pt = CGPoint(x: dest.x + Constants.kQuoteCornerRadius * 0.5, y: dest.y)
        stripe.addArc(withCenter: pt, radius: Constants.kQuoteCornerRadius * 0.5, startAngle: CGFloat.pi, endAngle: CGFloat.pi * 0.5, clockwise: false)
        // Give it some width and color.
        stripe.lineWidth = Constants.kQuoteCornerRadius
        self.stripeColor.setStroke()
        stripe.stroke()

        // Draw string
        let drawAt = CGPoint(x: Constants.kHorizontalTextOffset + Constants.kQuoteCornerRadius, y: Constants.kVerticalTextOffset)
        let rect = CGRect(origin: drawAt, size: textBounds.size)

        // Make sure we wrap the line if we don't have enough space.
        let drawingOpts: NSStringDrawingOptions = .usesLineFragmentOrigin.union(.truncatesLastVisibleLine)
        attributedString.draw(with: rect, options: drawingOpts, context: nil)
        context.restoreGState()

        guard let renderedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            assertionFailure("Could not create image from context")
            return UIImage()
        }
        return renderedImage
    }
}
