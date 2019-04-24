//
//  MessagesFlowLayout.swift
//  ios
//
//  Copyright (c) 2017-2018 MessageKit
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import MessageKit

class MessagesFlowLayout: MessagesCollectionViewFlowLayout {

    fileprivate lazy var customMessageSizeCalculator = CustomMessageSizeCalculator(layout: self)

    override func cellSizeCalculatorForItem(at indexPath: IndexPath) -> CellSizeCalculator {
        //        if isSectionReservedForTypingBubble(indexPath.section) {
        //            return typingMessageSizeCalculator
        //        }
        let message = messagesDataSource.messageForItem(at: indexPath, in: messagesCollectionView)
        if case .custom = message.kind {
            return customMessageSizeCalculator
        }
        return super.cellSizeCalculatorForItem(at: indexPath)
    }

    override func messageSizeCalculators() -> [MessageSizeCalculator] {
        var superCalculators = super.messageSizeCalculators()
        // Append any of your custom `MessageSizeCalculator` if you wish for the convenience
        // functions to work such as `setMessageIncoming...` or `setMessageOutgoing...`
        superCalculators.append(customMessageSizeCalculator)
        return superCalculators
    }
}

fileprivate class CustomMessageSizeCalculator: MessageSizeCalculator {

    public override init(layout: MessagesCollectionViewFlowLayout? = nil) {
        super.init()
        self.layout = layout
    }

    open override func sizeForItem(at indexPath: IndexPath) -> CGSize {
        guard let layout = layout else { return .zero }
        let collectionViewWidth = layout.collectionView?.bounds.width ?? 0
        let contentInset = layout.collectionView?.contentInset ?? .zero
        let inset = layout.sectionInset.left + layout.sectionInset.right + contentInset.left + contentInset.right
        return CGSize(width: collectionViewWidth - inset, height: 44)
    }
}
