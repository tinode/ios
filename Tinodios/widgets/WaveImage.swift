//
//  WaveImage.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import UIKit
import Foundation

public protocol WaveImageDelegate: AnyObject {
    func invalidate(in: WaveImage)
}

public class WaveImage {
    // Bars and spacing sizes.
    private static let kLineWidth: Float = 3
    private static let kThumbRadius: Float = 4
    private static let kSpacing: Float = 1
    // Minimum time between redraws in milliseconds.
    private static let kMinFrameDuration = 30 // ms

    private var size: CGSize

    private var cachedImage: UIImage = UIImage()
    private var animationTimer: Timer?
    private var timerStartedAt: Date?
    private var positionStartedAt: Float?

    // Current thumb position as a fraction of the total 0..1
    private var seekPosition: Float = 0

    // Amplitude values received from the caller and resampled to fit the screen.
    private var buffer: [Float] = []
    // Count of amplitude values actually added to the buffer.
    private var contains: Int = 0
    // Entry point in buffer (buffer is a circular buffer).
    private var index: Int = 0
    // Array of 2 values for each amplitude bar: start point, end point.
    private var bars: [CGPoint] = []
    // Maximum number of bars which fit onto canvas.
    private var maxBars: Int = 0
    // Canvas width which fits whole number of bars.
    private var effectiveWidth: Int = 0
    // Extra padding on the left to avoid clipping the thumb.
    private var leftPadding: Int = Int(WaveImage.kThumbRadius - 1)
    // If the Drawable is animated.
    private var running: Bool  = false

    // Duration of a single animation frame: about two pixels at a time, but no shorter than kMinFrameDuration.
    private var frameDuration: Int = WaveImage.kMinFrameDuration

    public var pastBarColor: CGColor
    public var futureBarColor: CGColor
    public var thumbColor: CGColor

    public weak var delegate: WaveImageDelegate?

    // Duration of the audio in milliseconds.
    public var duration: Int = 0 {
        didSet {
            // Recalculate frame duration (2 pixels per frame but not shorter than kMinFrameDuration).
            frameDuration = max(duration / effectiveWidth * 2, WaveImage.kMinFrameDuration)
        }
    }

    // Original preview data to use for drawing the bars.
    public var original: Data? {
        didSet {
            self.update(recalc: true)
        }
    }

    // MARK: - Initializers

    public init(size: CGSize, data: Data?) {
        pastBarColor = CGColor.init(gray: 0.7, alpha: 0.9)
        futureBarColor = CGColor.init(gray: 0.50, alpha: 0.9)
        thumbColor = UIColor.link.cgColor

        maxBars = Int((Float(size.width) - WaveImage.kSpacing - Float(leftPadding)) / (WaveImage.kLineWidth + WaveImage.kSpacing))

        effectiveWidth = Int(Float(maxBars) * (WaveImage.kLineWidth + WaveImage.kSpacing) + WaveImage.kSpacing)
        self.size = CGSize(width: size.width, height: size.height)

        defer {
            // Must be deferred otherwise observer is not called.
            self.original = data ?? Data(count: maxBars)
        }
    }

    convenience public init(size: CGSize, count: Int) {
        self.init(size: size, data: Data(count: count))
    }

    /// Current image.
    public var image: UIImage? {
        return cachedImage
    }

    /// Update image with optionally recalculating the data.
    public func update(recalc: Bool) {
        if recalc {
            if let val = original {
                buffer = WaveImage.resampleBars(src: val, dstLen: maxBars)
            } else {
                buffer = []
            }
            contains = buffer.count
            recalcBars()
        }
        cachedImage = renderWaveImage(bounds: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        delegate?.invalidate(in: self)
    }

    /// Start playback animation.
    public func play() {
        if self.animationTimer != nil {
            // Animation is already running.
            return
        }
        if duration <= 0 {
            return
        }

        self.timerStartedAt = Date()
        self.positionStartedAt = self.seekPosition
        self.animationTimer = Timer.scheduledTimer(timeInterval: Double(frameDuration) * 0.001, target: self, selector: #selector(animateFrame), userInfo: nil, repeats: true)
    }

    /// Pause playback animation.
    public func pause() {
        self.animationTimer?.invalidate()
        self.animationTimer = nil
        self.timerStartedAt = nil
        self.positionStartedAt = nil
    }

    /// Move thumb to initial position and stop animation.
    public func reset() {
        pause()
        seekTo(0)
    }

    /// Move thumb to specified position and refresh the image.
    @discardableResult
    public func seekTo(_ pos: Float) -> Bool {
        if self.duration <= 0 {
            return false
        }

        let newPos = min(0.999, max(0, pos))
        if self.seekPosition != newPos {
            self.seekPosition = newPos
            if timerStartedAt != nil {
                self.timerStartedAt = Date()
                self.positionStartedAt = self.seekPosition
            }
            update(recalc: false)
            return true
        }
        return false
    }

    /// Add another bar to waveform.
    public func put(_ amplitude: Float) {
        if contains < buffer.count {
            buffer[index + contains] = amplitude
            contains += 1
        } else {
            index += 1
            index %= buffer.count
            buffer[index] = amplitude
        }
        recalcBars()
        delegate?.invalidate(in: self)
    }

    @objc func animateFrame(timer: Timer) {
        if self.duration <= 0 {
            return
        }

        guard let startedAt = self.timerStartedAt, let initPosition = self.positionStartedAt else { return }
        let pos = initPosition - 1000 * Float(startedAt.timeIntervalSinceNow) / Float(duration)
        if pos >= 1 {
            pause()
        }
        seekTo(pos)
    }

    // Calculate vertices of amplitude bars.
    private func recalcBars() {
        if buffer.isEmpty {
            return
        }

        let height = Float(self.size.height)
        if effectiveWidth < 1 || height < 1 {
            return
        }

        bars = []
        for i in 0 ..< contains {
            let amp = max(buffer[(index + i) % contains], 0)

            // startX, endX
            let x = Float(Float(1.0) + Float(leftPadding) + Float(i) * (WaveImage.kLineWidth + WaveImage.kSpacing) + WaveImage.kLineWidth * Float(0.5))
            // Y length
            let y = amp * height * 0.9
            // starting point
            bars.append(CGPoint(x: Double(x), y: Double((height - y) * 0.5)))
            bars.append(CGPoint(x: Double(x), y: Double((height + y) * 0.5)))
        }
    }

    // Get thumb position for level.
    private func seekPositionToX() -> Float {
        let base: Float = Float(bars.count) / 2.0 * seekPosition
        return Float(bars[Int(base * 2)].x) + (base - floor(base)) * (WaveImage.kLineWidth + WaveImage.kSpacing);
    }

    // Quick and dirty resampling of the original preview bars into a smaller (or equal) number of bars we can display here.
    // The bar height is normalized to 0..1.
    private static func resampleBars(src: Data, dstLen: Int) -> [Float] {
        guard !src.isEmpty else {
            return [Float].init(repeating: 0.01, count: dstLen)
        }

        var dst = [Float].init(repeating: 0, count: dstLen)
        // Resampling factor. Could be lower or higher than 1.
        // src = 100, dst = 200, factor = 0.5
        // src = 200, dst = 100, factor = 2.0
        let factor: Float = Float(src.count) / Float(dst.count)
        var maxAmp: Float = -1
        for i in 0 ..< dst.count {
            let lo: Int = Int(Float(i) * factor) // low bound
            let hi: Int = Int(Float(i + 1) * factor) // high bound
            if hi == lo {
                dst[i] = Float(src[lo])
            } else {
                var amp: Float = 0
                for j in lo ..< hi {
                    amp += Float(src[j])
                }
                dst[i] = max(0, amp / Float(hi - lo))
            }
            maxAmp = max(dst[i], maxAmp)
        }

        if maxAmp > 0 {
            for i in 0 ..< dst.count {
                dst[i] = dst[i] / maxAmp
            }
            return dst
        }

        return [Float].init(repeating: 0.01, count: dstLen)
    }

    // Create button as image
    private func renderWaveImage(bounds: CGRect) -> UIImage {
        if bars.isEmpty {
            return UIImage()
        }

        UIGraphicsBeginImageContextWithOptions(CGSize(width: bounds.width, height: bounds.height), false, UIScreen.main.scale)

        defer { UIGraphicsEndImageContext() }
        let context = UIGraphicsGetCurrentContext()!

        context.saveGState()

        context.clip(to: bounds)

        // UIBezierPath with rounded corners
        let path = UIBezierPath()
        path.lineCapStyle = .round
        path.lineWidth = CGFloat(WaveImage.kLineWidth)

        if seekPosition <= 0 {
            // Draw all bars in one color.
            for i in stride(from: 0, to: bars.count, by: 2) {
                path.move(to: bars[i])
                path.addLine(to: bars[i+1])
            }
            context.setStrokeColor(self.futureBarColor)
            path.stroke()
        } else {
            // Draw past - future bars and thumb on top of them.
            let dividedAt = Int(Float(bars.count) * 0.5 * seekPosition) * 2

            // Already played amplitude bars.
            context.setStrokeColor(self.pastBarColor)
            for i in stride(from: 0, to: dividedAt, by: 2) {
                path.move(to: bars[i])
                path.addLine(to: bars[i+1])
            }
            path.stroke()

            // Not yet played amplitude bars.
            path.removeAllPoints()
            context.setStrokeColor(self.futureBarColor)
            for i in stride(from: dividedAt, to: bars.count, by: 2) {
                path.move(to: bars[i])
                path.addLine(to: bars[i+1])
            }
            path.stroke()
        }

        if self.duration > 0 {
            // Draw thumb.
            context.setFillColor(self.thumbColor)
            let size = CGFloat(WaveImage.kThumbRadius) * 2
            let x = seekPositionToX()
            UIBezierPath(ovalIn: CGRect(x: CGFloat(x) - size / 2, y: bounds.height * 0.5 - size / 2, width: size, height: size)).fill()
        }

        context.restoreGState()

        guard let renderedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            assertionFailure("Could not create image from context")
            return UIImage()
        }
        return renderedImage
    }
}
