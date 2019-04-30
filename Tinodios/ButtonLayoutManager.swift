//
//  ButtonLayoutManager.swift
//  Tinodios
//
//  Created by Gene Sokolov on 29/04/2019.
//  Copyright © 2019 Tinode. All rights reserved.
//
//  This is an NSLayoutManager for drawing button-like background
//  around NSAttributedString with .NSAttributedString.Key.button attribute
//

import Foundation
import UIKit

class ButtonLayoutManager: NSLayoutManager {

    // Draws a background with rounded corners.
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        let range = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        self.textStorage?.enumerateAttribute(NSAttributedString.Key.buttonBackground, in: range, using: { (value, range, stop) in
            if value != nil {
                let color: UIColor = value as! UIColor

                let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let container = self.textContainer(forGlyphAt: glyphRange.location,
                                                   effectiveRange: nil)

                // draw background
                let context = UIGraphicsGetCurrentContext();
                context!.saveGState()
                context!.translateBy(x: origin.x, y: origin.y)
                context!.setFillColor(color.cgColor)
                let rect = self.boundingRect(forGlyphRange: glyphRange, in: container!)

                // UIBezierPath with rounded corners
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 100)
                path.fill()
                context!.restoreGState()
            }
        })
    }
}

extension NSAttributedString.Key {
    static let buttonBackground = NSAttributedString.Key(rawValue: "buttonBackground")
}

