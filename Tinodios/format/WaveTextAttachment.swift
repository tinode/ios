//
//  WaveTextAttachment.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import UIKit
import Foundation

class WaveTextAttachment: EntityTextAttachment {
    // Bars and spacing sizes.
    private static let kLineWidth: Float = 3
    private static let kThumbRadius: Float = 4
    private static let kSpacing: Float = 1
    // Minimum time between redraws in milliseconds.
    private static let kMinFrameDuration = 50 // ms

    /// Container to be notified when the image is changed.
    private weak var textContainer: NSTextContainer?

    private var cachedImage: UIImage = UIImage()
    private var animationTimer: Timer?
    private var timerStartedAt: Date?
    private var positionStartedAt: Float?

    public var pastBarColor: CGColor
    public var futureBarColor: CGColor
    public var thumbColor: CGColor


    // Duration of the audio in milliseconds.
    public var duration: Int = 0 {
        didSet {
            // Recalculate frame duration (2 pixels per frame but not shorter than kMinFrameDuration).
            frameDuration = max(duration / effectiveWidth * 2, WaveTextAttachment.kMinFrameDuration)
        }
    }

    // Current thumb position as a fraction of the total 0..1
    private var seekPosition: Float = 0

    // Original preview data to use for drawing the bars.
    private var original: Data? {
        didSet {
            self.update(recalc: true)
        }
    }

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
    private var leftPadding: Int = Int(WaveTextAttachment.kThumbRadius - 1)
    // If the Drawable is animated.
    private var running: Bool  = false

    // Duration of a single animation frame: about two pixels at a time, but no shorter than kMinFrameDuration.
    private var frameDuration: Int = WaveTextAttachment.kMinFrameDuration

    // MARK: - Initializers

    public init(frame rect: CGRect) {
        pastBarColor = CGColor.init(gray: 0.5, alpha: 1.0)
        futureBarColor = CGColor.init(gray: 0.40, alpha: 1.0)
        thumbColor = UIColor.link.cgColor

        super.init(data: nil, ofType: nil)

        maxBars = Int((Float(rect.width) - WaveTextAttachment.kSpacing - Float(leftPadding)) / (WaveTextAttachment.kLineWidth + WaveTextAttachment.kSpacing))

        effectiveWidth = Int(Float(maxBars) * (WaveTextAttachment.kLineWidth + WaveTextAttachment.kSpacing) + WaveTextAttachment.kSpacing)

        bounds = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience public init(frame rect: CGRect, data: Data?) {
        self.init(frame: rect)
        defer {
            // Must be deferred otherwise observer is not called.
            self.original = data
        }
    }

    public override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        // Keep reference to text container. It will be updated if image changes.
        self.textContainer = textContainer
        return cachedImage
    }

    /// Update image with optionally recalculating the data.
    public func update(recalc: Bool) {
        if recalc {
            if let val = original {
                buffer = WaveTextAttachment.resampleBars(src: val, dstLen: maxBars)
            } else {
                buffer = []
            }
            contains = buffer.count
            recalcBars()
        }
        cachedImage = renderWaveImage(bounds: bounds)
        DispatchQueue.main.async {
            // Force container redraw.
            let length = self.textContainer?.layoutManager?.textStorage?.length
            self.textContainer?.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: length ?? 1))
        }
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

        let height = Float(self.bounds.height)
        if effectiveWidth < 1 || height < 1 {
            return
        }

        // Values for scaling amplitude.
        guard let maxAmp = buffer.max(), maxAmp > 0 else {
            return
        }

        bars = []
        for i in 0 ..< contains {
            let amp = max(buffer[(index + i) % contains], 0)

            // startX, endX
            let x = Float(Float(1.0) + Float(leftPadding) + Float(i) * (WaveTextAttachment.kLineWidth + WaveTextAttachment.kSpacing) + WaveTextAttachment.kLineWidth * Float(0.5))
            // Y length
            let y = amp / maxAmp * height * 0.9
            // starting point
            bars.append(CGPoint(x: Double(x), y: Double((height - y) * 0.5)))
            bars.append(CGPoint(x: Double(x), y: Double((height + y) * 0.5)))
        }
    }

    // Get thumb position for level.
    private func seekPositionToX() -> Float {
        let base: Float = Float(bars.count) / 2.0 * seekPosition
        return Float(bars[Int(base * 2)].x) + (base - floor(base)) * (WaveTextAttachment.kLineWidth + WaveTextAttachment.kSpacing);
    }

    // Quick and dirty resampling of the original preview bars into a smaller (or equal) number of bars we can display here.
    private static func resampleBars(src: Data, dstLen: Int) -> [Float] {
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
        }

        return dst
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
        path.lineWidth = CGFloat(WaveTextAttachment.kLineWidth)

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
            let size = CGFloat(WaveTextAttachment.kThumbRadius) * 2
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
