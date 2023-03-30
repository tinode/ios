//
//  DotSelectorImage.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import Foundation
import UIKit

public class DotSelectorDrawable {
    public var selectedColor: CGColor
    public var normalColor: CGColor

    var dotCount: Int = 0
    var selected: Int = 0

    // Original size of the image
    private let size: CGSize
    // Bounds of the image with insets
    private var bounds: CGRect

    private var cachedImage: UIImage = UIImage()
    
    public init(size: CGSize) {
        selectedColor = UIColor.link.cgColor
        normalColor = CGColor.init(gray: 0.50, alpha: 0.9)

        self.size = CGSize(width: size.width, height: size.height)
        self.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    /// Playback histogram.
    public convenience init(size: CGSize, dots: Int, selected: Int) {
        self.init(size: size)

        self.dotCount = dots
        self.selected = selected
    }

    /// Current image.
    public var image: UIImage? {
        return cachedImage
    }

    public func setDotCount(count: Int) {
        if dotCount != count {
            dotCount = count
            if let image = renderImage() {
                cachedImage = image
            }
        }
    }

    public func select(index: Int) {
        if selected != index {
            selected = index
            if let image = renderImage() {
                cachedImage = image
            }
        }
    }

    private func renderImage() -> UIImage? {
        if dotCount <= 0 {
            return nil
        }

        UIGraphicsBeginImageContextWithOptions(CGSize(width: size.width, height: size.height), false, UIScreen.main.scale)

        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        context.saveGState()
        context.clip(to: bounds)

        let yStep = size.height / CGFloat(dotCount + 1)
        let radius = min(size.width / 4.0, yStep - 4)
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
