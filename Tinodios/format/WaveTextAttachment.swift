//
//  WaveTextAttachment.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import UIKit
import Foundation

class WaveTextAttachment: EntityTextAttachment {
    /// Container to be notified when the image is changed.
    private weak var textContainer: NSTextContainer?

    /// Image producer.
    private var waveImage: WaveImage!

    // Duration of the audio in milliseconds.
    public var duration: Int {
        get {
            return waveImage.duration
        }
        set {
            waveImage.duration = newValue
        }
    }

    public var pastBarColor: CGColor {
        get {
            return waveImage.pastBarColor
        }
        set {
            waveImage.pastBarColor = newValue
        }
    }
    public var futureBarColor: CGColor {
        get {
            return waveImage.futureBarColor
        }
        set {
            waveImage.futureBarColor = newValue
        }
    }
    public var thumbColor: CGColor {
        get {
            return waveImage.thumbColor
        }
        set {
            waveImage.thumbColor = newValue
        }
    }

    // MARK: - Initializers

    public init(frame rect: CGRect) {
        super.init(data: nil, ofType: nil)
        bounds = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)

        self.waveInit(frame: rect, data: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience public init(frame rect: CGRect, data: Data?) {
        self.init(frame: rect)

        self.waveInit(frame: rect, data: data)
    }

    private func waveInit(frame rect: CGRect, data: Data?) {
        waveImage = WaveImage(size: CGSize(width: rect.width, height: rect.height), data: data)
        waveImage.delegate = self
        waveImage.pastBarColor = CGColor.init(gray: 0.5, alpha: 1.0)
        waveImage.futureBarColor = CGColor.init(gray: 0.40, alpha: 1.0)
        waveImage.thumbColor = UIColor.link.cgColor
    }

    public override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        // Keep reference to text container. It will be updated if image changes.
        self.textContainer = textContainer
        return waveImage.image
    }

    /// Update image with optionally recalculating the data.
    public func update(recalc: Bool) {
        waveImage.update(recalc: recalc)
    }

    /// Start playback animation.
    public func play() {
        waveImage.play()
    }

    /// Pause playback animation.
    public func pause() {
        waveImage.pause()
    }

    /// Move thumb to initial position and stop animation.
    public func reset() {
        waveImage.resetPlayback()
    }

    /// Move thumb to specified position and refresh the image.
    @discardableResult
    public func seekTo(_ pos: Float) -> Bool {
        return waveImage.seekTo(pos)
    }
}

extension WaveTextAttachment: WaveImageDelegate {
    func invalidate(in: WaveImage) {
        DispatchQueue.main.async {
            // Force container redraw.
            let length = self.textContainer?.layoutManager?.textStorage?.length
            self.textContainer?.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: length ?? 1))
        }
    }
}
