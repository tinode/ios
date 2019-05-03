//
//  MessageLayoutAttributes.swift
//  Tinodios
//
//  Created by Gene Sokolov on 03/05/2019.
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

class MessageLayoutAttributes: UICollectionViewLayoutAttributes {

    // MARK: - Properties

    public var avatarSize: CGSize = .zero

    public var containerSize: CGSize = .zero
    public var containerPadding: UIEdgeInsets = .zero

    public var messageLabelFont: UIFont = UIFont.preferredFont(forTextStyle: .body)
    public var messageLabelInsets: UIEdgeInsets = .zero

    public var newDateLabelSize: CGSize = .zero

    public var senderNameLabelSize: CGSize = .zero

    // MARK: - Methods

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! MessageLayoutAttributes
        copy.avatarSize = avatarSize
        copy.containerSize = containerSize
        copy.containerPadding = containerPadding
        copy.messageLabelFont = messageLabelFont
        copy.messageLabelInsets = messageLabelInsets
        copy.newDateLabelSize = newDateLabelSize
        copy.senderNameLabelSize = senderNameLabelSize
        return copy
    }

    override func isEqual(_ object: Any?) -> Bool {
        if let attributes = object as? MessageLayoutAttributes {
            return super.isEqual(object) && attributes.avatarSize == avatarSize
                && attributes.containerSize == containerSize
                && attributes.containerPadding == containerPadding
                && attributes.messageLabelFont == messageLabelFont
                && attributes.messageLabelInsets == messageLabelInsets
                && attributes.newDateLabelSize == newDateLabelSize
                && attributes.senderNameLabelSize == senderNameLabelSize
        } else {
            return false
        }
    }
}
