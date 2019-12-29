//
//  MsgRange.swift
//  TinodeSDK
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

// Represents a contiguous range of message sequence ids:
// inclusive on the left - exclusive on the right.
public class MsgRange: Codable {
    public var low: Int
    public var hi: Int?
    public var lower: Int { return low }
    public var upper: Int { return hi ?? lower + 1 }

    public init() {
        self.low = 0
        self.hi = nil
    }
    public init(id: Int) {
        self.low = id
        self.hi = nil
    }
    public init(low: Int, hi: Int?) {
        self.low = low
        self.hi = hi
    }
    public init(from another: MsgRange) {
        self.low = another.low
        self.hi = another.hi
    }

    private static func cmp(_ val1: Int?, _ val2: Int?) -> Int {
        return (val1 ?? 0) - (val2 ?? 0)
    }
    public func compare(to other: MsgRange) -> Int {
        let rl = MsgRange.cmp(self.low, other.low)
        return rl == 0 ? MsgRange.cmp(other.hi, self.hi) : rl
    }
    /**
     * Collapse multiple possibly overlapping ranges into as few ranges non-overlapping
     * ranges as possible: [1..6],[2..4],[5..7] -> [1..7].
     *
     * The input array of ranges must be sorted.
     *
     * @param ranges ranges to collapse
     * @return non-overlapping ranges.
     */
    public static func collapse(_ ranges: [MsgRange]) -> [MsgRange] {
        guard ranges.count > 1 else { return ranges }

        var result = [MsgRange(from: ranges[0])]
        for i in 1..<ranges.count {
            if MsgRange.cmp(result.last!.low, ranges[i].low) == 0 {
                // Same starting point.

                // Earlier range is guaranteed to be wider or equal to the later range,
                // collapse two ranges into one (by doing nothing)
                continue
            }
            // Check for full or partial overlap
            let prev_hi = result.last!.upper
            if prev_hi >= ranges[i].lower {
                // Partial overlap: previous hi is above or equal to current low.
                let cur_hi = ranges[i].upper
                if cur_hi > prev_hi {
                    // Current range extends further than previous, extend previous.
                    result.last!.hi = cur_hi
                }
                // Otherwise the next range is fully within the previous range, consume it by doing nothing.
                continue
            }

            // No overlap. Just copy the values.
            result.append(MsgRange(from: ranges[i]))
        }
        return result
    }
    /**
     * Get maximum enclosing range. The input array must be sorted.
     */
    public static func enclosing(for ranges: [MsgRange]?) -> MsgRange? {
        guard let ranges = ranges, !ranges.isEmpty else { return nil }
        let first = MsgRange(from: ranges[0])
        if ranges.count > 1 {
            first.hi = ranges.last!.upper
        } else if first.hi == nil {
            first.hi = first.upper
        }
        return first
    }
}
