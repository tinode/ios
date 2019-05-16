//
//  MessageViewLayout.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

protocol MessageViewLayoutDelegate: class {
}

class MessageViewLayout: UICollectionViewFlowLayout {
    
    weak var delegate: MessageViewLayoutDelegate!

    override class var layoutAttributesClass: AnyClass {
        return MessageViewLayoutAttributes.self
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

    // Not used just yet.
    var deliveryMarkerFrame: CGRect = .zero
    var timestampFrame: CGRect = .zero

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! MessageViewLayoutAttributes

        copy.avatarFrame = avatarFrame
        copy.senderNameFrame = senderNameFrame
        copy.containerFrame = containerFrame
        copy.contentFrame = contentFrame
        copy.deliveryMarkerFrame = deliveryMarkerFrame
        copy.timestampFrame = timestampFrame
        return copy
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MessageViewLayoutAttributes else { return false }
        
        return super.isEqual(object) && other.avatarFrame == avatarFrame &&
            other.senderNameFrame == senderNameFrame &&
            other.containerFrame == containerFrame &&
            other.contentFrame == contentFrame &&
            other.deliveryMarkerFrame == deliveryMarkerFrame &&
            other.timestampFrame == timestampFrame
    }
}
