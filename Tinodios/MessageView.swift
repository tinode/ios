//
//  MessageView.swift
//  Tinodios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit

class MessageView: UICollectionView {

    // MARK: - Properties

    weak var cellDelegate: MessageCellDelegate?
    weak var foregroundView: UIView?

    // MARK: - Initializers

    public override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        if traitCollection.userInterfaceStyle == .dark {
            backgroundColor = .black
        } else {
            backgroundColor = .white
        }

        // Reusable message cells
        register(MessageCell.self, forCellWithReuseIdentifier: String(describing: MessageCell.self))

        // Gesture recognizer: short tap, long tap.
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGesture.delaysTouchesBegan = true
        addGestureRecognizer(tapGesture)
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleTapGesture(_:))))
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
        let contentHeight = collectionViewLayout.collectionViewContentSize.height
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

    /// Handle gesture, return true when gestureRecognizer's touch point is in a cell.
    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        return indexPathForItem(at: gesture.location(in: self)) != nil
    }

    /// Show notification that the conversation is empty
    public func toggleNoMessagesNote(on show: Bool) {
        if show {
            let messageLabel = UILabel(frame: CGRect(x: 0, y: 0, width: self.bounds.size.width, height: self.bounds.size.height))
            messageLabel.text = NSLocalizedString("No messages in the conversation", comment: "Placeholder in empty chat")
            messageLabel.textColor = .darkGray
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            messageLabel.font = .preferredFont(forTextStyle: .headline)
            messageLabel.sizeToFit()

            self.backgroundView = messageLabel
        } else {
            self.backgroundView = nil
        }
    }

    /// Adds a blurring overlay over the messages
    /// with "No access to messages" label in the center.
    public func showNoAccessOverlay(withMessage message: String?) {
        // Make sure there's no foreground overlay yet.
        guard self.foregroundView == nil else { return }

        // Blurring layer over the messages.
        let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        blurEffectView.alpha = 1
        blurEffectView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(blurEffectView)

        // Pin the edges to the superview edges.
        NSLayoutConstraint.activate([
            blurEffectView.topAnchor.constraint(equalTo: self.topAnchor),
            blurEffectView.bottomAnchor.constraint(equalTo: self.safeAreaLayoutGuide.bottomAnchor),
            blurEffectView.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor),
            blurEffectView.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor)])

        // "No access to messages" text.
        let noAccessLabel = UILabel()
        noAccessLabel.text = NSLocalizedString("No access to messages", comment: "No read access in chat")
        noAccessLabel.numberOfLines = 0
        noAccessLabel.textAlignment = .center
        noAccessLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        noAccessLabel.translatesAutoresizingMaskIntoConstraints = false
        noAccessLabel.sizeToFit()
        blurEffectView.contentView.addSubview(noAccessLabel)

        var offset: CGFloat = 0
        if let message = message {
            let messageLabel = UILabel()
            messageLabel.text = message
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            messageLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            messageLabel.sizeToFit()
            blurEffectView.contentView.addSubview(messageLabel)

            offset = messageLabel.bounds.height * 0.75
            // Pin it to the superview slightly below center.
            NSLayoutConstraint.activate([
                messageLabel.centerXAnchor.constraint(equalTo: blurEffectView.centerXAnchor),
                messageLabel.centerYAnchor.constraint(equalTo: blurEffectView.centerYAnchor, constant: offset)])
        }
        // Pin it to the superview center (or above center in case of a message).
        NSLayoutConstraint.activate([
            noAccessLabel.centerXAnchor.constraint(equalTo: blurEffectView.centerXAnchor),
            noAccessLabel.centerYAnchor.constraint(equalTo: blurEffectView.centerYAnchor, constant: -offset)])

        // Disable user interaction for the message view.
        self.isUserInteractionEnabled = false

        self.foregroundView = blurEffectView
    }

    public func removeNoAccessOverlay() {
        guard self.foregroundView != nil else { return }
        self.foregroundView!.removeFromSuperview()
        self.foregroundView = nil
        self.isUserInteractionEnabled = true
    }
}
