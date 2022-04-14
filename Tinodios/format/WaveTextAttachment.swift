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

    public var pastBarColor: CGColor
    public var futureBarColor: CGColor
    public var thumbColor: CGColor

    // Duration of the audio in milliseconds.
    private var duration: Int = 0

    // Current thumb position as a fraction of the total 0..1
    private var seekPosition: Float = -1

    // Original preview data to use for drawing the bars.
    private var original: Data? {
        didSet {
            if let val = original {
                buffer = WaveTextAttachment.resampleBars(src: val, dstLen: maxBars)
            } else {
                buffer = []
            }
            contains = buffer.count
            recalcBars()
            image = renderWaveImage(bounds: bounds)
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
    private var leftPadding: Int = 0
    // If the Drawable is animated.
    private var running: Bool  = false

    // Duration of a single animation frame: about two pixels at a time, but no shorter than kMinFrameDuration.
    private var frameDuration: Int = WaveTextAttachment.kMinFrameDuration

    // MARK: - Initializers

    public init(frame rect: CGRect) {
        pastBarColor = CGColor.init(gray: 0.5, alpha: 1.0)
        futureBarColor = CGColor.init(gray: 0.40, alpha: 1.0)
        thumbColor = CGColor.init(gray: 1, alpha: 1.0)

        super.init(data: nil, ofType: nil)

        maxBars = Int((Float(rect.width) - WaveTextAttachment.kSpacing - Float(leftPadding)) / (WaveTextAttachment.kLineWidth + WaveTextAttachment.kSpacing))

        effectiveWidth = Int(Float(maxBars) * (WaveTextAttachment.kLineWidth + WaveTextAttachment.kSpacing) + WaveTextAttachment.kSpacing)

        // Recalculate frame duration (2 pixels per frame).
        frameDuration = max(duration / effectiveWidth * 2, WaveTextAttachment.kMinFrameDuration)

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
        let base: Float = Float(bars.count) / 2.0 * (seekPosition - 0.01)
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

        print("Rendering image")

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
            context.setStrokeColor(self.pastBarColor)
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

            // Draw thumb.
            context.setStrokeColor(self.thumbColor)
            UIBezierPath(ovalIn: CGRect(x: CGFloat(seekPositionToX()), y: bounds.height * 0.5, width: CGFloat(WaveTextAttachment.kThumbRadius) * 2, height: CGFloat(WaveTextAttachment.kThumbRadius) * 2)).stroke()
        }

        context.restoreGState()

        guard let renderedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            assertionFailure("Could not create image from context")
            return UIImage()
        }
        return renderedImage
    }
}
