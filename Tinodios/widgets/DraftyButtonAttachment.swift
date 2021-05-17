//
//  DraftyButtonAttachment.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

// An NSTextAttachment which draws a button-like image for use in Drafty forms.
class DraftyButtonAttachment : NSTextAttachment {
    private enum Constants {
        // Mimumum button width in points
        static let kMinWidth: CGFloat = 40
        // Button height mulitplier (forntHeight * 1.4)
        static let kHeightMultiplier: CGFloat = 1.4
        // Button width padding in characters.
        static let kWidthPadding: Int = 3
        static let kDefaultButtonBackgroundColor: UIColor = UIColor.white.withAlphaComponent(0.8)
    }

    var payload: URL?
    var attributedString: NSAttributedString

    let traceBorder: Bool
    let widthPadding: Int
    let heightMultiplier: CGFloat
    let backgroundColor: UIColor

    init(face: NSAttributedString, data: URL?, traceBorder: Bool = false, widthPadding: Int = Constants.kWidthPadding, heightMultiplier: CGFloat = Constants.kHeightMultiplier, backgroundColor: UIColor = Constants.kDefaultButtonBackgroundColor) {
        attributedString = face
        payload = data
        self.traceBorder = traceBorder
        self.widthPadding = widthPadding
        self.heightMultiplier = heightMultiplier
        self.backgroundColor = backgroundColor
        super.init(data: nil, ofType: "public.text")
        let rect = face.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), context: nil)

        // Calculate button width: string width + some characters extra, but no less than kMinWidth
        let width = max(Constants.kMinWidth, rect.width / CGFloat(face.length) * CGFloat(face.length + self.widthPadding))

        bounds = CGRect(x: 0, y: 0, width: width, height: rect.height * heightMultiplier)
        image = renderButtonImage(textRect: rect)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Create button as image
    private func renderButtonImage(textRect: CGRect) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: bounds.width, height: bounds.height), false, UIScreen.main.scale)

        defer { UIGraphicsEndImageContext() }
        let context = UIGraphicsGetCurrentContext()!

        context.saveGState()
        context.clip(to: bounds)

        // Draw background.
        context.setFillColor(self.backgroundColor.cgColor)
        // UIBezierPath with rounded corners
        let bkgRect = bounds.insetBy(dx: 1, dy: 1)
        let path = UIBezierPath(roundedRect: bkgRect, cornerRadius: bkgRect.height * 0.5)
        path.fill()
        if traceBorder {
            path.stroke(with: .colorBurn, alpha: 0.5)
        }
        // Draw string
        attributedString.draw(at: CGPoint(x: (bounds.width - textRect.width) * 0.5, y: (bounds.height - textRect.height) * 0.5))
        context.restoreGState()

        guard let renderedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            assertionFailure("Could not create image from context")
            return UIImage()
        }
        return renderedImage
    }
}

