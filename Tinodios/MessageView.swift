//
//  MessageCollectionView.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

class MessageView: UICollectionView {

    // MARK: - Properties

    weak var cellDelegate: MessageCellDelegate?

    // MARK: - Initializers

    public override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        backgroundColor = .white

        // Reusable message cells
        register(MessageCell.self, forCellWithReuseIdentifier: String(describing: MessageCell.self))

        // Gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGesture.delaysTouchesBegan = true
        addGestureRecognizer(tapGesture)
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(frame: .zero, collectionViewLayout: MessageViewLayout())
    }

    public convenience init() {
        self.init(frame: .zero, collectionViewLayout: MessageViewLayout())
    }

    // MARK: - Methods

    @objc
    func handleTapGesture(_ gesture: UIGestureRecognizer) {
        guard gesture.state == .ended else { return }

        let touchLocation = gesture.location(in: self)
        guard let indexPath = indexPathForItem(at: touchLocation) else { return }

        if let cell = cellForItem(at: indexPath) as? MessageCell {
            cell.handleTapGesture(gesture)
        }
    }

    func scrollToBottom(animated: Bool = false) {
        let contentHeight = contentSize.height //collectionViewLayout.collectionViewContentSize.height
        performBatchUpdates(nil) { _ in
            self.scrollRectToVisible(CGRect(x: 0, y: contentHeight - 1, width: 1, height: 1), animated: animated)
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

extension MessageView {

    /// Show notification that the conversation is empty
    public func showNoMessagesNote(_ show: Bool) {
        if show {
            let messageLabel = UILabel(frame: CGRect(x: 0, y: 0, width: self.bounds.size.width, height: self.bounds.size.height))
            messageLabel.text = "No messages in the conversation"
            messageLabel.textColor = .darkText
            messageLabel.numberOfLines = 0;
            messageLabel.textAlignment = .center;
            messageLabel.font = .preferredFont(forTextStyle: .body)
            messageLabel.sizeToFit()

            self.backgroundView = messageLabel
        } else {
            self.backgroundView = nil
        }
    }
}
