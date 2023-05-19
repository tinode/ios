//
//  MsgRange.swift
//  TinodeSDK
//
//  Copyright © 2019-2023 Tinode LLC. All rights reserved.
//

import Foundation

// Represents a contiguous range of message sequence ids:
// inclusive on the left - exclusive on the right.
public class MsgRange: Codable, Comparable {
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

    public static func == (lhs: MsgRange, rhs: MsgRange) -> Bool {
        return lhs.lower == rhs.lower && lhs.upper == rhs.upper
    }

    public static func < (lhs: MsgRange, rhs: MsgRange) -> Bool {
        var diff = lhs.low - rhs.low
        if diff == 0 {
            diff = rhs.upper - lhs.upper
        }
        return diff < 0
    }

    // Attempts to extend current range with id.
    private func extend(withId id: Int) -> Bool {
        if low == id {
            return true
        }
        if let h = hi {
            if h == id {
                hi = h + 1
                return true
            }
            return false
        }
        // hi == nil
        if id == low + 1 {
            hi = id + 1
            return true
        }
        return false
    }

    // Removes hi if it's meaningless.
    private func normalize() {
        if let h = hi, h <= low + 1 {
            hi = nil
        }
    }

    public static func toRanges(_ list: [Int]) -> [MsgRange]? {
        guard !list.isEmpty else { return nil }
        let slist = list.sorted()
        var result: [MsgRange] = []
        var curr = MsgRange(id: slist.first!)
        for i in 1..<slist.count {
            let id = slist[i]
            if !curr.extend(withId: id) {
                curr.normalize()
                result.append(curr)
                // Start new range.
                curr = MsgRange(id: id)
            }
        }
        result.append(curr)
        return result
    }

    /// Collapse multiple possibly overlapping ranges into as few non-overlapping
    /// ranges as possible: [1..6],[2..4],[5..7] -> [1..7].
    /// The input array of ranges must be sorted.
    ///
    /// - Parameters:
    ///  - ranges ranges to collapse
    /// - Returns array of non-overlapping ranges.
    public static func collapse(_ ranges: [MsgRange]) -> [MsgRange] {
        guard ranges.count > 1 else { return ranges }

        var result = [MsgRange(from: ranges[0])]
        for i in 1..<ranges.count {
            if result.last!.lower == ranges[i].lower {
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
    /// Get maximum enclosing range. The input array must be sorted.
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

    /// Find gaps in the given array of non-overlapping ranges.
    /// The input must be sorted and overlaps removed.
    public static func gaps(ranges: [MsgRange]) -> [MsgRange] {
        guard ranges.count >= 2 else { return [] }

        var gaps: [MsgRange] = []

        for i in 1..<ranges.count {
            if ranges[i-1].upper < ranges[i].lower {
                // Gap found
                gaps.append(MsgRange(low: ranges[i-1].upper, hi: ranges[i].lower))
            }
        }

        return gaps
    }

    /// Cut 'clip' range out of the 'src' range.
    ///
    /// - Parameters:
    ///  - src source range to subtract from.
    ///  - clip range to subtract.
    /// - Returns array with 0, 1 or 2 elements.
    public static func clip(src: MsgRange, clip: MsgRange) -> [MsgRange] {
        guard clip.upper >= src.lower && clip.lower < src.upper else {
            // Clip is completely outside of src, no intersection.
            return [src]
        }

        if clip.low <= src.low {
            if clip.upper >= src.upper {
                // The source range is completely inside the clipping range.
                return []
            }
            // Partial clipping at the top.
            return [MsgRange(low: src.lower, hi: clip.upper)]
        }

        // Range on the lower end.
        let lower = MsgRange(low: src.lower, hi: clip.lower)
        if clip.upper < src.upper {
            return [lower, MsgRange(low: clip.upper, hi: src.upper)];
        }
        return [lower]
    }
}
