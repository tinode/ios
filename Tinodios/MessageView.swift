//
//  MessageCollectionView.swift
//  Tinodios
//
//  Created by Gene Sokolov on 03/05/2019.
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

open class MessageView: UICollectionView {

    // MARK: - Properties

    open weak var messageCellDelegate: MessageCellDelegate?

    // MARK: - Initializers

    public override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        backgroundColor = .white
        // Reusable message cells
        register(TextMessageCell.self, forCellWithReuseIdentifier: String(describing: TextMessageCell.self))

        // Gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGesture.delaysTouchesBegan = true
        addGestureRecognizer(tapGesture)
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(frame: .zero, collectionViewLayout: MessagesCollectionViewFlowLayout())
    }

    public convenience init() {
        self.init(frame: .zero, collectionViewLayout: MessagesCollectionViewFlowLayout())
    }

    // MARK: - Methods

    @objc
    func handleTapGesture(_ gesture: UIGestureRecognizer) {
        guard gesture.state == .ended else { return }

        let touchLocation = gesture.location(in: self)
        guard let indexPath = indexPathForItem(at: touchLocation) else { return }

        let cell = cellForItem(at: indexPath) as? MessageContentCell
        cell?.handleTapGesture(gesture)
    }

    func scrollToBottom(animated: Bool = false) {
        let collectionViewContentHeight = collectionViewLayout.collectionViewContentSize.height

        performBatchUpdates(nil) { _ in
            self.scrollRectToVisible(CGRect(x: 0, y: collectionViewContentHeight - 1, width: 1, height: 1), animated: animated)
        }
    }

    func reloadDataAndKeepOffset() {
        // stop scrolling
        setContentOffset(contentOffset, animated: false)

        // calculate the offset and reloadData
        let beforeContentSize = contentSize
        reloadData()
        layoutIfNeeded()
        let afterContentSize = contentSize

        // reset the contentOffset after data is updated
        let newOffset = CGPoint(
            x: contentOffset.x + (afterContentSize.width - beforeContentSize.width),
            y: contentOffset.y + (afterContentSize.height - beforeContentSize.height))
        setContentOffset(newOffset, animated: false)
    }
}
