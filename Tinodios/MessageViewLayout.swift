//
//  MessageViewLayout.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

protocol MessageViewLayoutDelegate: class {
    func collectionView(_ collectionView: UICollectionView, fillAttributes: MessageViewLayoutAttributes)
}

class MessageViewLayout: UICollectionViewLayout {

    // MARK: private vars

    weak var delegate: MessageViewLayoutDelegate!

    fileprivate var contentHeight: CGFloat = 0

    fileprivate var attributeCache: [MessageViewLayoutAttributes] = []

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
        if attributeCache.count == itemCount {
            // Item count did not change. Skip update
            return
        }

        // Calculate and cache cell attributes.
        attributeCache.removeAll(keepingCapacity: true)
        var yOffset: CGFloat = 0 //collectionView.layoutMargins.top
        let leftMargin = collectionView.layoutMargins.left
        for item in 0 ..< itemCount {
            let indexPath = IndexPath(item: item, section: 0)
            let attr = MessageViewLayoutAttributes(forCellWith: indexPath)
            delegate.collectionView(collectionView, fillAttributes: attr)

            // Adjust frame origin: add margin and shift down.
            attr.frame.origin.y += yOffset
            attr.frame.origin.x += leftMargin
            attributeCache.append(attr)
            yOffset = attr.frame.maxY + attr.cellSpacing
            contentHeight = attr.frame.maxY
        }
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var visibleAttributes = [UICollectionViewLayoutAttributes]()
        // Loop through the cache and look for items in the rect
        for attr in attributeCache {
            if attr.frame.intersects(rect) {
                visibleAttributes.append(attr)
            }
        }

        return visibleAttributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return attributeCache[indexPath.item]
    }

    override func invalidateLayout() {
        super.invalidateLayout()

        attributeCache.removeAll(keepingCapacity: true)
    }

    // MARK: helper methods
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
            other.newDateFrame == newDateFrame &&
            other.cellSpacing == cellSpacing &&
            other.progressViewFrame == progressViewFrame
    }
}
