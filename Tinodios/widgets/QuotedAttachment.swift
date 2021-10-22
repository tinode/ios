//
//  QuotedAttachment.swift
//  Tinodios
//
//  Copyright © 2021 Tinode. All rights reserved.
//

import UIKit

// An NSTextAttachment which draws renders quoted Drafty document.
class QuotedAttachment: NSTextAttachment {
    private enum Constants {
        // Mimumum button width in points
        static let kMinWidth: CGFloat = 40
        // Button height mulitplier (forntHeight * 1.4)
        static let kHeightMultiplier: CGFloat = 1.4
        // Button width padding in characters.
        static let kWidthPadding: CGFloat = 3
        static let kDefaultButtonBackgroundColor: UIColor = UIColor(fromHexCode: 0x20333333)
        static let kDefaultStripeColor: UIColor = UIColor(fromHexCode: 0xFF00897B)
    }

    var attributedString: NSAttributedString

    let widthPadding: CGFloat
    let heightMultiplier: CGFloat
    let backgroundColor: UIColor
    let stripeColor: UIColor

    init(quotedText: NSAttributedString, widthPadding: CGFloat = Constants.kWidthPadding, heightMultiplier: CGFloat = Constants.kHeightMultiplier, backgroundColor: UIColor = Constants.kDefaultButtonBackgroundColor, stripeColor: UIColor = Constants.kDefaultStripeColor, verticalOffset: CGFloat = 0) {
        attributedString = quotedText
        self.widthPadding = widthPadding
        self.heightMultiplier = heightMultiplier
        self.backgroundColor = backgroundColor
        self.stripeColor = stripeColor
        super.init(data: nil, ofType: "public.text")

        let textSize = TextSizeHelper().computeSize(for: quotedText, within: CGFloat.greatestFiniteMagnitude)

        let absolutePosition = quotedText.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), context: nil)

        let textBounds =
            CGRect(origin: absolutePosition.origin, size: textSize)

        // Calculate button width: string width + some characters extra, but no less than kMinWidth
        let width = max(Constants.kMinWidth, textBounds.width / CGFloat(quotedText.length) * (CGFloat(quotedText.length) + self.widthPadding))

        image = renderQuote(textBounds: textBounds, buttonBounds: CGRect(x: 0, y: 0, width: width, height: textBounds.height * heightMultiplier))
        bounds = CGRect(x: 0, y: verticalOffset, width: width, height: textBounds.height * heightMultiplier)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Create button as image
    private func renderQuote(textBounds: CGRect, buttonBounds: CGRect) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: buttonBounds.width, height: buttonBounds.height), false, UIScreen.main.scale)

        defer { UIGraphicsEndImageContext() }
        let context = UIGraphicsGetCurrentContext()!

        context.saveGState()
        context.clip(to: buttonBounds)

        // Draw background.
        context.setFillColor(self.backgroundColor.cgColor)
        // UIBezierPath with rounded corners
        let bkgRect = buttonBounds.insetBy(dx: 1, dy: 1)

        let radius = min(bkgRect.height * 0.1, CGFloat(3))
        let path = UIBezierPath(roundedRect: bkgRect, cornerRadius: radius)
        path.fill()

        // Draw the stripe on the left of the quote box.
        let stripe = UIBezierPath()
        let start = CGPoint(x: bkgRect.minX + radius, y: bkgRect.minY + radius)
        // Top rounded corner.
        stripe.addArc(withCenter: start, radius: radius * 0.5, startAngle: 1.5 * CGFloat.pi, endAngle: CGFloat.pi, clockwise: false)
        // Vertical stripe body.
        stripe.move(to: CGPoint(x: bkgRect.minX + radius * 0.5, y: bkgRect.minY + radius))
        let dest = CGPoint(x: bkgRect.minX + radius * 0.5, y: bkgRect.maxY - radius)
        stripe.addLine(to: dest)
        // Botton rounded corner.
        let pt = CGPoint(x: dest.x + radius * 0.5, y: dest.y)
        stripe.addArc(withCenter: pt, radius: radius * 0.5, startAngle: CGFloat.pi, endAngle: CGFloat.pi * 0.5, clockwise: false)
        // Give it some width and color.
        stripe.lineWidth = radius
        self.stripeColor.setStroke()
        stripe.stroke()

        // Draw string
        attributedString.draw(at: CGPoint(x: (buttonBounds.width - textBounds.width) * 0.5, y: (buttonBounds.height - textBounds.height) * 0.5))
        context.restoreGState()

        guard let renderedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            assertionFailure("Could not create image from context")
            return UIImage()
        }
        return renderedImage
    }
}
