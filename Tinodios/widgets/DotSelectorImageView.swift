//
//  DotSelectorImageView.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import UIKit

@IBDesignable
public class DotSelectorImageView: UIImageView {
    private static let kSelectedColor = UIColor.link.cgColor
    private static let kNormalColor = CGColor.init(gray: 0.50, alpha: 0.9)

    private static let kCornerRadius:CGFloat = 20

    public var selectedColor: CGColor
    public var normalColor: CGColor

    var dotCount: Int = 3
    var selected: Int = 0

    // MARK: - Initializers.

    override public init(frame: CGRect) {
        selectedColor = DotSelectorImageView.kSelectedColor
        normalColor = DotSelectorImageView.kNormalColor

        super.init(frame: frame)
        self.image = self.renderImage()

        // Make left-side corners round.
        self.layer.cornerRadius = DotSelectorImageView.kCornerRadius
        self.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }

    required public init?(coder aDecoder: NSCoder) {
        selectedColor = DotSelectorImageView.kSelectedColor
        normalColor = DotSelectorImageView.kNormalColor

        super.init(coder: aDecoder)
        self.image = self.renderImage()

        // Make left-side corners round.
        self.layer.cornerRadius = DotSelectorImageView.kCornerRadius
        self.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }

    // MARK: - support display in storyboard.
    override public func prepareForInterfaceBuilder() {
        if let image = renderImage() {
            self.image = image
        }
    }

    public func setDotCount(count: Int) {
        if dotCount != count {
            dotCount = count
            if let image = renderImage() {
                self.image = image
            }
        }
    }

    public func select(index: Int) {
        if selected != index {
            selected = index
            if let image = renderImage() {
                self.image = image
            }
        }
    }

    private func renderImage() -> UIImage? {
        if dotCount <= 0 {
            return nil
        }

        UIGraphicsBeginImageContextWithOptions(CGSize(width: frame.width, height: frame.height), false, UIScreen.main.scale)

        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        context.saveGState()
        context.clip(to: bounds)

        let yStep = frame.height / CGFloat(dotCount + 1)
        let radius = min(frame.width / 4.0, yStep - 4)
        let yStart = bounds.minY + yStep
        let sel = dotCount - selected - 1
        for i in 0 ..< dotCount {
            context.setFillColor(i == sel ? selectedColor : normalColor)
            context.addArc(center: CGPoint(x: bounds.midX, y: yStart + yStep * CGFloat(i)), radius: radius + (i == sel ? 1 : 0), startAngle: 0, endAngle: .pi * 2, clockwise: true)
        }

        context.restoreGState()

        guard let renderedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            assertionFailure("Could not create image from context")
            return UIImage()
        }
        return renderedImage
    }
}
