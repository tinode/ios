//
//  WaveImageView.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import UIKit

@IBDesignable
public class WaveImageView: UIImageView, WaveImageDelegate {
    private var wave: WaveImage!

    // MARK: - Initializers.

    override public init(frame: CGRect) {
        self.wave = WaveImage(size: CGSize(width: frame.width, height: frame.height), data: nil)
        super.init(frame: frame)
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.wave = WaveImage(size: CGSize(width: frame.width, height: frame.height), data: nil)
    }

    // MARK: - Instance methods.

    public func put(amplitude: Float) {
        self.wave.put(amplitude)
        self.image = self.wave.image
    }

    public func invalidate(in: WaveImage) {
    }
}
