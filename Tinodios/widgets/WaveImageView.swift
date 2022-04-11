//
//  WaveImageView.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import UIKit
import Foundation

class WaveImageView: UIImageView {

    // Bars and spacing sizes.
    private static let kLineWidth: Float = 3
    private static let kSpacing: Float = 1


    // Amplitude values received from the caller and resampled to fit the screen.
    private var buffer: [Float]
    // Count of amplitude values actually added to the buffer.
    private var contains: Int
    // Entry point in mBuffer (mBuffer is a circular buffer).
    private var index: Int
    // Array of 4 values for each amplitude bar: startX, startY, stopX, stopY.
    private var bars: [Float]
    // Canvas width which fits whole number of bars.
    private var effectiveWidth: Int
    // Padding on the left.
    private var leftPadding: Int = 0
    // If the Drawable is animated.
    private var running: Bool  = false

    private var size: Rect

    // Calculate vertices of amplitude bars.
    private func recalcBars() {
        if buffer.isEmpty {
            return
        }

        let height = size.height()
        if effectiveWidth <= 0 || height <= 0 {
            return
        }

        // Values for scaling amplitude.
        guard let maxAmp = buffer.max(), maxAmp > 0 else {
            return
        }

        bars = [Float].init(repeating: 0, count: contains * 4)
        for i in 0 ..< contains {
            var amp = max(buffer[(index + i) % contains], 0)

            // startX, endX
            let x = leftPadding + 1.0 + i * (WaveImageView.kLineWidth + WaveImageView.kSpacing) + WaveImageView.kLineWidth * 0.5
            // Y length
            let y = amp / maxAmp * height * 0.9
            // startX
            bars[i * 4] = x
            // startY
            bars[i * 4 + 1] = (height - y) * 0.5
            // stopX
            bars[i * 4 + 2] = x
            // stopY
            bars[i * 4 + 3] = (height + y) * 0.5
        }
    }

    // Get thumb position for level.
    private func seekPositionToX() -> Float {
        let base: Float = bars.count / 4.0 * (seekPosition - 0.01)
        return bars[base * 4] + (base - Int(base)) * (kLineWidth + kSpacing);
    }

    // Quick and dirty resampling of the original preview bars into a smaller (or equal) number of bars we can display here.
    private static func resampleBars(src: [Int8], dst: [Float]) {
        // Resampling factor. Could be lower or higher than 1.
        let factor: Float = Float(src.size) / dst.size
        var maxAmp: Float = -1
        // src = 100, dst = 200, factor = 0.5
        // src = 200, dst = 100, factor = 2.0
        for i in 0 ..< dst.size {
            let lo = Int(i * factor) // low bound;
            let hi = Int((i + 1) * factor) // high bound;
            if hi == lo {
                dst[i] = src[lo]
            } else {
                let amp: Float = 0
                for j in lo ..< hi {
                    amp += src[j]
                }
                dst[i] = max(0, amp / (hi - lo));
            }
            maxAmp = max(dst[i], maxAmp)
        }

        if (maxAmp > 0) {
            for i in 0 ..< dst.size {
                dst[i] = dst[i] / maxAmp
            }
        }
    }
}
