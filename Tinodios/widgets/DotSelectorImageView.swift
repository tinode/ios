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
    private static let kNormalColor = CGColor.init(gray: 0.70, alpha: 0.9)
    private static let kDotRadius: CGFloat = 3.5
    private static let kCornerRadius:CGFloat = 10

    public var selectedColor: CGColor
    public var normalColor: CGColor

    var dotCount: Int = 0 {
        didSet {
            if let image = renderImage() {
                self.image = image
            }
        }
    }
    var selected: Int = 0 {
        didSet {
            if let image = renderImage() {
                self.image = image
            }
        }
    }

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
        self.layer.masksToBounds = true
        self.layer.cornerRadius = DotSelectorImageView.kCornerRadius
        self.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
    }

    // MARK: - support display in storyboard.
    override public func prepareForInterfaceBuilder() {
        if let image = renderImage() {
            self.image = image
        }
    }

    // MARK: - catch bounds change
    override public var bounds: CGRect {
        didSet {
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

        context.setFillColor(UIColor.secondarySystemBackground.cgColor)
        context.fill(bounds)

        let yStep = bounds.height / CGFloat(dotCount + 1)
        let radius: CGFloat = DotSelectorImageView.kDotRadius
        let yStart = bounds.minY + yStep
        let sel = dotCount - selected - 1
        for i in 0 ..< dotCount {
            context.setFillColor(i == sel ? selectedColor : normalColor)
            context.addArc(center: CGPoint(x: bounds.midX, y: yStart + yStep * CGFloat(i)), radius: radius + (i == sel ? 0.5 : 0), startAngle: 0, endAngle: .pi * 2, clockwise: true)
            context.fillPath()
        }

        context.restoreGState()

        guard let renderedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            assertionFailure("Could not create image from context")
            return UIImage()
        }
        return renderedImage
    }
}
