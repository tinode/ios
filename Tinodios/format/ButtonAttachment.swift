//
//  ButtonAttachment.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK

// An NSTextAttachment which draws a button-like image for use in Drafty forms.
class ButtonAttachment: NSTextAttachment {
    private enum Constants {
        // Mimumum button width in points
        static let kMinWidth: CGFloat = 40
        // Button height mulitplier (forntHeight * 1.4)
        static let kHeightMultiplier: CGFloat = 1.4
        // Button width padding in characters.
        static let kWidthPadding: CGFloat = 3
        static let kDefaultButtonBackgroundColor: UIColor = UIColor.white.withAlphaComponent(0.8)
    }

    var payload: URL?
    var faceText: NSAttributedString

    let traceBorder: Bool
    let widthPadding: CGFloat
    let heightMultiplier: CGFloat
    let backgroundColor: UIColor

    init(face: NSAttributedString, data: URL?, traceBorder: Bool = false, widthPadding: CGFloat = Constants.kWidthPadding, heightMultiplier: CGFloat = Constants.kHeightMultiplier, backgroundColor: UIColor = Constants.kDefaultButtonBackgroundColor, verticalOffset: CGFloat = 0) {
        faceText = face
        payload = data
        self.traceBorder = traceBorder
        self.widthPadding = widthPadding
        self.heightMultiplier = heightMultiplier
        self.backgroundColor = backgroundColor
        super.init(data: nil, ofType: "public.text")
        let textBounds = face.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), context: nil)

        // Calculate button width: string width + some characters extra, but no less than kMinWidth
        let width = max(Constants.kMinWidth, textBounds.width / CGFloat(face.length) * (CGFloat(face.length) + self.widthPadding))

        image = renderButtonImage(textBounds: textBounds, buttonBounds: CGRect(x: 0, y: 0, width: width, height: textBounds.height * heightMultiplier))
        bounds = CGRect(x: 0, y: verticalOffset, width: width, height: textBounds.height * heightMultiplier)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Create button as image
    private func renderButtonImage(textBounds: CGRect, buttonBounds: CGRect) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: buttonBounds.width, height: buttonBounds.height), false, UIScreen.main.scale)

        defer { UIGraphicsEndImageContext() }
        let context = UIGraphicsGetCurrentContext()!

        context.saveGState()
        context.clip(to: buttonBounds)

        // Draw background.
        context.setFillColor(self.backgroundColor.cgColor)
        // UIBezierPath with rounded corners
        let bkgRect = buttonBounds.insetBy(dx: 1, dy: 1)
        let path = UIBezierPath(roundedRect: bkgRect, cornerRadius: bkgRect.height * 0.5)
        path.fill()
        if traceBorder {
            path.stroke(with: .colorBurn, alpha: 0.67)
        }
        // Draw string
        faceText.draw(at: CGPoint(x: (buttonBounds.width - textBounds.width) * 0.5, y: (buttonBounds.height - textBounds.height) * 0.5))
        context.restoreGState()

        guard let renderedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            assertionFailure("Could not create image from context")
            return UIImage()
        }
        return renderedImage
    }
}
