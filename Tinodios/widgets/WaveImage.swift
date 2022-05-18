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

/// WaveImage generates an image of a bar histogram. It supports two modes:
/// 1. Playback.
///   The histogram is added at once. The image can show a seek thumb and seek position can be animated.
/// 2. Recording
///   The histogram is added one bar at a time, once the number of bars exceeds the capacity,
///   the oldest bar is dropped. The histogram is not seekable.
public class WaveImage {
    // Bars and spacing sizes.
    private static let kLineWidth: CGFloat = 3
    private static let kThumbRadius: CGFloat = 4
    private static let kSpacing: CGFloat = 1
    // Minimum time between redraws in milliseconds.
    private static let kMinFrameDuration = 30 // ms

    // Original size of the image
    private let size: CGSize
    // Bounds of the image with insets
    private var bounds: CGRect

    private var cachedImage: UIImage = UIImage()
    private var animationTimer: Timer?
    private var timerStartedAt: Date?
    private var positionStartedAt: CGFloat?

    // Current thumb position as a fraction of the total 0..1
    private var seekPosition: CGFloat = 0

    // Raw amplitude values.
    private var buffer: [CGFloat] = []
    // Entry point in buffer (buffer is a circular buffer).
    private var index: Int = 0
    // Array of 2 values for each amplitude bar: start point, end point.
    private var bars: [CGPoint] = []
    // Maximum number of bars which fit onto canvas.
    private var maxBars: Int = 0
    // Canvas width which fits whole number of bars.
    private var effectiveWidth: Int = 0
    // Extra padding on the left to avoid clipping the thumb.
    private var leftPadding: CGFloat = WaveImage.kThumbRadius - 1
    // If the Drawable is animated.
    private var running: Bool  = false

    // Duration of a single animation frame: about two pixels at a time, but no shorter than kMinFrameDuration.
    private var frameDuration: Int = WaveImage.kMinFrameDuration

    // MARK: - Public variables

    public var pastBarColor: CGColor
    public var futureBarColor: CGColor
    public var thumbColor: CGColor

    public weak var delegate: WaveImageDelegate?

    /// Duration of the audio in milliseconds.
    public var duration: Int = 0 {
        didSet {
            // Recalculate frame duration (2 pixels per frame but not shorter than kMinFrameDuration).
            frameDuration = max(duration / effectiveWidth * 2, WaveImage.kMinFrameDuration)
        }
    }

    /// Image insets.
    public var insets: UIEdgeInsets? {
        didSet {
            self.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            if let newVal = self.insets {
                self.bounds = self.bounds.inset(by: newVal)
            }
            self.calcMaxBars()
            self.update(recalc: true)
        }
    }

    /// Original playback preview data to use for drawing the bars.
    public var playbackData: Data? {
        didSet {
            if playbackData != nil {
                self.update(recalc: true)
            }
        }
    }

    /// Current image.
    public var image: UIImage? {
        return cachedImage
    }

    // MARK: - Initializers

    /// Playback histogram.
    public convenience init(size: CGSize, data: Data?) {
        self.init(size: size)
        defer {
            // Must use defer otherwise the observer is not called.
            self.playbackData = data ?? Data()
        }
    }

    /// Recording histogram.
    public init(size: CGSize) {
        pastBarColor = CGColor.init(gray: 0.7, alpha: 0.9)
        futureBarColor = CGColor.init(gray: 0.50, alpha: 0.9)
        thumbColor = UIColor.link.cgColor

        self.size = CGSize(width: size.width, height: size.height)
        self.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        self.calcMaxBars()
    }

    // MARK: - Public methods

    /// Update image with optionally recalculating the visualization from the original dataset.
    public func update(recalc: Bool) {
        if recalc {
            resampleBars()
            recalcBars()
        }

        if let image = renderWaveImage() {
            cachedImage = image
            delegate?.invalidate(in: self)
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
    public func resetPlayback() {
        pause()
        seekTo(0)
    }

    /// Move thumb to specified position and refresh the image.
    @discardableResult
    public func seekTo(_ pos: Float) -> Bool {
        if self.duration <= 0 {
            return false
        }

        let newPos = CGFloat(min(0.999, max(0, pos)))
        if self.seekPosition != newPos {
            self.seekPosition = newPos
            if timerStartedAt != nil {
                self.timerStartedAt = Date()
                self.positionStartedAt = CGFloat(self.seekPosition)
            }
            update(recalc: false)
            return true
        }
        return false
    }

    /// Add another bar to recording waveform.
    public func put(_ amplitude: Float) {
        if buffer.count < maxBars {
            buffer.append(CGFloat(amplitude))
        } else {
            index = (index + 1) % buffer.count
            buffer[index] = CGFloat(amplitude)
        }
        update(recalc: true)
    }

    // MARK: - Private methods.

    @objc func animateFrame(timer: Timer) {
        if self.duration <= 0 {
            return
        }

        guard let startedAt = self.timerStartedAt, let initPosition = self.positionStartedAt else { return }
        let pos = initPosition - 1000 * CGFloat(startedAt.timeIntervalSinceNow) / CGFloat(duration)
        if pos >= 1 {
            pause()
        }
        seekTo(Float(pos))
    }

    // Calculate vertices of amplitude bars.
    private func recalcBars() {
        if buffer.isEmpty {
            return
        }

        let height = self.bounds.height
        if effectiveWidth < 1 || height < 1 {
            return
        }

        var maxAmp = self.buffer.max() ?? 1
        if maxAmp < 0.01 {
            maxAmp = 1
        }
        bars = []
        for i in 0 ..< buffer.count {
            let amp = max(buffer[(index + i) % buffer.count], 0) / maxAmp

            // startX, endX
            let x = 1.0 + leftPadding + CGFloat(i) * (WaveImage.kLineWidth + WaveImage.kSpacing) + WaveImage.kLineWidth * 0.5 + bounds.minX
            // Y length
            let y = amp * height * 0.9
            // Starting point.
            bars.append(CGPoint(x: x, y: (height - y) * 0.5 + bounds.minY))
            // Ending point.
            bars.append(CGPoint(x: x, y: (height + y) * 0.5 + bounds.minY))
        }
    }

    // Calculate the maximum number of bars tht fits into the image
    private func calcMaxBars() {
        self.maxBars = Int((self.bounds.width - WaveImage.kSpacing - leftPadding) / (WaveImage.kLineWidth + WaveImage.kSpacing))
        self.effectiveWidth = Int(CGFloat(self.maxBars) * (WaveImage.kLineWidth + WaveImage.kSpacing) + WaveImage.kSpacing)
        let shrinkBy = self.buffer.count - self.maxBars
        if shrinkBy > 0 {
            // The new image is smaller, leave only the most recent values.
            var clipped: [CGFloat] = []
            for i in shrinkBy..<self.buffer.count {
                clipped.append(self.buffer[(self.index + i) % self.buffer.count])
            }
            self.buffer = clipped
            self.index = 0
        }
    }

    // Get thumb position for level.
    private func seekPositionToX() -> CGFloat {
        let base: CGFloat = CGFloat(bars.count) / 2.0 * seekPosition
        return CGFloat(bars[Int(base * 2)].x) + (base - floor(base)) * (WaveImage.kLineWidth + WaveImage.kSpacing);
    }

    // Quick and dirty resampling of the original preview bars into a smaller (or equal) number of bars we can display here.
    // The bar height is normalized to 0..1.
    private func resampleBars() {
        guard let src = self.playbackData else { return }

        // Generate blank playback bars by downsampling or upsampling original data.
        var dst: [CGFloat] = [CGFloat].init(repeating: 0, count: maxBars)
        if !src.isEmpty {
            // Resampling factor. Could be lower or higher than 1.
            // src = 100, dst = 200, factor = 0.5
            // src = 200, dst = 100, factor = 2.0
            let factor: CGFloat = CGFloat(src.count) / CGFloat(dst.count)
            for i in 0 ..< dst.count {
                let lo: Int = Int(CGFloat(i) * factor) // low bound
                let hi: Int = Int(CGFloat(i + 1) * factor) // high bound
                if hi == lo {
                    dst[i] = CGFloat(src[lo])
                } else {
                    var amp: CGFloat = 0
                    for j in lo ..< hi {
                        amp += CGFloat(src[j])
                    }
                    dst[i] = max(0, amp / CGFloat(hi - lo))
                }
            }
        }
        self.buffer = dst
    }

    // Create button as image
    private func renderWaveImage() -> UIImage? {
        if bars.isEmpty {
            return nil
        }

        UIGraphicsBeginImageContextWithOptions(CGSize(width: size.width, height: size.height), false, UIScreen.main.scale)

        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

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
            let dividedAt = Int(round(CGFloat(bars.count) * 0.5 * seekPosition)) * 2

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
            let diameter = CGFloat(WaveImage.kThumbRadius) * 2
            let x = seekPositionToX()
            UIBezierPath(ovalIn: CGRect(x: CGFloat(x) - diameter / 2, y: bounds.height * 0.5 - diameter / 2 + bounds.minY, width: diameter, height: diameter)).fill()
        }

        context.restoreGState()

        guard let renderedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            assertionFailure("Could not create image from context")
            return UIImage()
        }
        return renderedImage
    }
}
