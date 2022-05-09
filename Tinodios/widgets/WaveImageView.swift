//
//  WaveImageView.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import UIKit

@IBDesignable
public class WaveImageView: UIImageView {
    private var wave: WaveImage!

    // When the current bar started from the beginning of the record.
    private var barStarted: TimeInterval = 0
    private var ampAccumulator: Float = 0

    // Duration represented by one bar.
    public var barDuration: TimeInterval = 0.1

    // MARK: - Initializers.

    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.wave = WaveImage(size: CGSize(width: frame.width, height: frame.height))
        self.image = self.wave.image
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.wave = WaveImage(size: CGSize(width: frame.width, height: frame.height))
        self.image = self.wave.image
    }

    // MARK: public vars

    @IBInspectable
    public var waveInsets: UIEdgeInsets = UIEdgeInsets() {
        didSet {
            self.wave.insets = self.waveInsets
        }
    }

    // MARK: - Instance methods.

    public func put(amplitude: Float, atTime: TimeInterval) {
        if atTime < barStarted + barDuration {
            self.ampAccumulator += amplitude
            return
        }

        self.wave.put(self.ampAccumulator)
        self.image = self.wave.image

        self.barStarted += barDuration
        self.ampAccumulator = 0
    }

    public func reset() {
        self.wave = WaveImage(size: CGSize(width: frame.width, height: frame.height))
        self.image = self.wave.image
        self.barStarted = 0
        self.ampAccumulator = 0
    }
}
