//
//  MessageViewLayout.swift
//  Tinodios
//
//  Copyright © 2019-2023 Tinode LLC. All rights reserved.
//

import UIKit

protocol MessageViewLayoutDelegate: AnyObject {
    func collectionView(_ collectionView: UICollectionView, fillAttributes: MessageViewLayoutAttributes)
}

class MessageViewLayout: UICollectionViewFlowLayout {

    // MARK: private vars

    weak var delegate: MessageViewLayoutDelegate!

    fileprivate var contentHeight: CGFloat = 0

    fileprivate var attrCellCache: [MessageViewLayoutAttributes] = []
    fileprivate var attrHeader: MessageViewLayoutAttributes!

    fileprivate var contentWidth: CGFloat {
        guard let collectionView = collectionView else {
            return 0
        }
        let insets = collectionView.contentInset
        return collectionView.bounds.width - (insets.left + insets.right)
    }

    // MARK: overriden methods

    override class var layoutAttributesClass: AnyClass {
        return MessageViewLayoutAttributes.self
    }

    override var collectionViewContentSize: CGSize {
        return CGSize(width: contentWidth, height: contentHeight)
    }

    override func prepare() {
        guard let collectionView = collectionView else {
            return
        }

        let itemCount = collectionView.numberOfItems(inSection: 0)
        if attrCellCache.count == itemCount {
            // Item count did not change. Skip update
            return
        }

        // Calculate and cache cell attributes.
        attrCellCache.removeAll(keepingCapacity: true)
        let leftMargin = collectionView.layoutMargins.left
        self.attrHeader = MessageViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, with: IndexPath(item: 0, section: 0))
        delegate.collectionView(collectionView, fillAttributes: self.attrHeader)

        var yOffset: CGFloat = self.attrHeader.frame.maxY
        for item in 0 ..< itemCount {
            let indexPath = IndexPath(item: item, section: 0)
            let cellAttr = MessageViewLayoutAttributes(forCellWith: indexPath)
            delegate.collectionView(collectionView, fillAttributes: cellAttr)
            // Adjust frame origin: add margin and shift down.
            cellAttr.frame.origin.y += yOffset
            cellAttr.frame.origin.x += leftMargin
            attrCellCache.append(cellAttr)
            yOffset = cellAttr.frame.maxY + cellAttr.cellSpacing
            contentHeight = cellAttr.frame.maxY
        }
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var visibleAttributes = [UICollectionViewLayoutAttributes]()
        if attrCellCache.isEmpty {
            return visibleAttributes
        }

        visibleAttributes.append(adjustHeaderAttributesIfNeeded(attrHeader))

        // Loop through the cache and look for items in the rect
        for attr in attrCellCache {
            if attr.frame.intersects(rect) {
                visibleAttributes.append(attr)
            }
        }

        return visibleAttributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard attrCellCache.indices.contains(indexPath.item) else {
            // FIXME: this shouldn't happen.
            Cache.log.error("MessageViewLayout attributes cache missing index %d", indexPath.item)
            return MessageViewLayoutAttributes(forCellWith: indexPath)
        }
        return attrCellCache[indexPath.item]
    }

    override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return adjustHeaderAttributesIfNeeded(attrHeader)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }

    override func invalidateLayout() {
        super.invalidateLayout()

        attrCellCache.removeAll(keepingCapacity: true)
    }

    // MARK: helper methods
    private func adjustHeaderAttributesIfNeeded(_ attr: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        guard let collectionView = collectionView else { return attr }
        guard attr.indexPath.section == 0 else { return attr }

        attr.frame = CGRect(origin: CGPoint(x: 0, y: max(0, collectionView.contentOffset.y)), size: attr.size)
        return attr
    }
}

class MessageViewLayoutAttributes: UICollectionViewLayoutAttributes {
    // Avatar position and size
    var avatarFrame: CGRect = .zero
    // Sender name label position and size
    var senderNameFrame: CGRect = .zero

    // Message bubble position and size
    var containerFrame: CGRect = .zero

    // Message content inside the bubble.
    var contentFrame: CGRect = .zero

    // Delivery marker.
    var deliveryMarkerFrame: CGRect = .zero

    // Timestamp.
    var timestampFrame: CGRect = .zero

    // Edited marker.
    var editedMarkerFrame: CGRect = .zero

    // Optional new date label above message bubble
    var newDateFrame: CGRect = .zero

    // Vertical spacing between cells
    var cellSpacing: CGFloat = 0

    // Progress bar.
    var progressViewFrame: CGRect = .zero

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! MessageViewLayoutAttributes

        copy.avatarFrame = avatarFrame
        copy.senderNameFrame = senderNameFrame
        copy.containerFrame = containerFrame
        copy.contentFrame = contentFrame
        copy.deliveryMarkerFrame = deliveryMarkerFrame
        copy.timestampFrame = timestampFrame
        copy.editedMarkerFrame = editedMarkerFrame
        copy.newDateFrame = newDateFrame
        copy.cellSpacing = cellSpacing
        copy.progressViewFrame = progressViewFrame
        return copy
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MessageViewLayoutAttributes else { return false }

        return super.isEqual(object) && other.avatarFrame == avatarFrame &&
            other.senderNameFrame == senderNameFrame &&
            other.containerFrame == containerFrame &&
            other.contentFrame == contentFrame &&
            other.deliveryMarkerFrame == deliveryMarkerFrame &&
            other.timestampFrame == timestampFrame &&
            other.editedMarkerFrame == editedMarkerFrame &&
            other.newDateFrame == newDateFrame &&
            other.cellSpacing == cellSpacing &&
            other.progressViewFrame == progressViewFrame
    }
}
