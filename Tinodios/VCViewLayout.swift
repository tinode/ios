//
//  VCViewController.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import UIKit

// Video conferencing participants.
class VCViewLayout: UICollectionViewLayout {
    enum SegmentStyle {
        // Segment occupies the full screen width.
        case fullWidth
        // Screen is shared by two segments of equal height.
        case fiftyFifty
    }

    func nextSegment(forRemainingCells cells: Int, prevSegment: SegmentStyle) -> SegmentStyle {
        return cells > 1 ? .fiftyFifty : .fullWidth
    }

    var contentBounds = CGRect.zero
    var cachedAttributes = [UICollectionViewLayoutAttributes]()

    override func prepare() {
        super.prepare()

        guard let collectionView = collectionView else { return }

        // Reset cached information.
        cachedAttributes.removeAll()
        contentBounds = CGRect(origin: .zero, size: collectionView.bounds.size)

        let count = collectionView.numberOfItems(inSection: 0)

        var currentIndex = 0
        var segment: SegmentStyle = count < 4 ? .fullWidth : .fiftyFifty
        var lastFrame: CGRect = .zero
        let cvWidth = collectionView.bounds.size.width
        // Video cells occupy at least a half of the screen vertically.
        let minHeight = collectionView.bounds.size.height / 2

        while currentIndex < count {
            let segmentFrame = CGRect(x: 0, y: lastFrame.maxY + 1.0, width: cvWidth, height: max(collectionView.bounds.size.height / CGFloat(count), minHeight))

            var segmentRects = [CGRect]()
            switch segment {
            case .fullWidth:
                segmentRects = [segmentFrame]

            case .fiftyFifty:
                let horizontalSlices = segmentFrame.dividedIntegral(fraction: 0.5, from: .minXEdge)
                segmentRects = [horizontalSlices.first, horizontalSlices.second]
            }

            // Create and cache layout attributes for calculated frames.
            for rect in segmentRects {
                let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: currentIndex, section: 0))
                attributes.frame = rect

                cachedAttributes.append(attributes)
                contentBounds = contentBounds.union(lastFrame)

                currentIndex += 1
                lastFrame = rect
            }
            contentBounds = contentBounds.union(lastFrame)

            // Determine the next segment style.
            segment = nextSegment(forRemainingCells: count - currentIndex, prevSegment: segment)
        }
    }

    override var collectionViewContentSize: CGSize {
        return contentBounds.size
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView = collectionView else { return false }
        return !newBounds.size.equalTo(collectionView.bounds.size)
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return cachedAttributes[indexPath.item]
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attributesArray = [UICollectionViewLayoutAttributes]()

        // Find any cell that sits within the query rect.
        guard let lastIndex = cachedAttributes.indices.last,
              let firstMatchIndex = binSearch(rect, start: 0, end: lastIndex) else { return attributesArray }

        // Starting from the match, loop up and down through the array until all the attributes
        // have been added within the query rect.
        for attributes in cachedAttributes[..<firstMatchIndex].reversed() {
            guard attributes.frame.maxY >= rect.minY else { break }
            attributesArray.append(attributes)
        }

        for attributes in cachedAttributes[firstMatchIndex...] {
            guard attributes.frame.minY <= rect.maxY else { break }
            attributesArray.append(attributes)
        }

        return attributesArray
    }

    // Perform a binary search on the cached attributes array.
    func binSearch(_ rect: CGRect, start: Int, end: Int) -> Int? {
        if end < start { return nil }

        var l = start
        var r = end
        while l <= r {
            let m = (l + r) / 2
            let attr = cachedAttributes[m]
            if attr.frame.intersects(rect) {
                return m
            }
            if attr.frame.maxY < rect.minY {
                l = m + 1
            } else {
                r = m - 1
            }
        }
        return nil
    }
}
