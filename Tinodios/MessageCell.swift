//
//  MessageCell.swift
//  Tinodios
//
//  Created by Gene Sokolov on 03/05/2019.
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

/// A protocol used to detect taps in the chat message.
protocol MessageCellDelegate: class {
    func didTapMessage(in cell: MessageCell)

    func didTapAvatar(in cell: MessageCell)
}

// Contains message bubble + avatar + delivery markers.
class MessageCell: UICollectionViewCell {

    // MARK: - Initializers

    public override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setupSubviews()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setupSubviews()
    }

    /// The image view with the avatar.
    var avatarView: RoundImageView = RoundImageView()

    /// The UIImageView with background being the bubble,
    /// holds the message's content view.
    var containerView: UIImageView = {
        let containerView = UIImageView()
        containerView.clipsToBounds = true
        containerView.layer.masksToBounds = true
        return containerView
    }()

    /// The message content
    var content: PaddedLabel = PaddedLabel()

    /// The label above the messageBubble which holds the date of conversation.
    var newDateLabel: PaddedLabel = PaddedLabel()

    /// The label under the messageBubble: sender's name in group topics.
    var senderNameLabel: PaddedLabel = PaddedLabel()

    /// Delivery marker.
    var deliveryMarker: UIImageView = UIImageView()

    /// Message timestamp.
    var timestampLabel: PaddedLabel = PaddedLabel()

    /// The `MessageCellDelegate` for the cell.
    weak var delegate: MessageCellDelegate?

    func setupSubviews() {
        contentView.addSubview(newDateLabel)
        contentView.addSubview(senderNameLabel)
        contentView.addSubview(containerView)
        containerView.addSubview(content)
        // containerView.addSubview(deliveryMarker)
        // containerView.addSubview(timestampLabel)
        contentView.addSubview(avatarView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        newDateLabel.text = nil
        senderNameLabel.text = nil
    }

    // MARK: - Configuration

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)

        guard let attributes = layoutAttributes as? MessageLayoutAttributes else { return }
        // Call this before other laying out other subviews
        layoutContainerView(with: attributes)
        layoutSenderNameLabel(with: attributes)
        layoutNewDateLabel(with: attributes)
        layoutAvatarView(with: attributes)
    }

    /// Handle tap gesture on contentView and its subviews.
    func handleTapGesture(_ gesture: UIGestureRecognizer) {
        let touchLocation = gesture.location(in: self)

        switch true {
        case containerView.frame.contains(touchLocation) && !cellContentView(canHandle: convert(touchLocation, to: containerView)):
            delegate?.didTapMessage(in: self)
        case avatarView.frame.contains(touchLocation):
            delegate?.didTapAvatar(in: self)
        default:
            break
        }
    }

    /// Handle long press gesture, return true when gestureRecognizer's touch point in `messageContainerView`'s frame
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let touchPoint = gestureRecognizer.location(in: self)
        guard gestureRecognizer.isKind(of: UILongPressGestureRecognizer.self) else { return false }
        return containerView.frame.contains(touchPoint)
    }

    /// Handle `ContentView`'s tap gesture, return false when `ContentView` doesn't needs to handle gesture
    func cellContentView(canHandle touchPoint: CGPoint) -> Bool {
        return false
    }

    // MARK: - Origin Calculations

    /// Positions the cell's `AvatarView`.
    /// - attributes: The `MessagesCollectionViewLayoutAttributes` for the cell.
    func layoutAvatarView(with attributes: MessageLayoutAttributes) {
        var origin: CGPoint = .zero

        // Left-bottom of the cell
        origin.y = attributes.frame.height - attributes.avatarSize.height

        avatarView.frame = CGRect(origin: origin, size: attributes.avatarSize)
    }

    /// Positions the cell's `containerView`.
    /// - attributes: The `MessagesCollectionViewLayoutAttributes` for the cell.
    func layoutContainerView(with attributes: MessageLayoutAttributes) {
        var origin: CGPoint = .zero

        origin.y = attributes.newDateLabelSize.height + attributes.containerPadding.top

        origin.x = attributes.avatarSize.width + attributes.containerPadding.left

        containerView.frame = CGRect(origin: origin, size: attributes.containerSize)

        content.textInsets = attributes.messageLabelInsets
        content.font = attributes.messageLabelFont
        content.frame = containerView.bounds

        // FIXME: lay out delivery marker and timestamp.
    }

    /// Positions the message bubble's top label.
    /// - attributes: The `MessagesCollectionViewLayoutAttributes` for the cell.
    func layoutNewDateLabel(with attributes: MessageLayoutAttributes) {
        newDateLabel.textAlignment = .center
        newDateLabel.textInsets = .zero

        let y = containerView.frame.minY - attributes.containerPadding.top - attributes.newDateLabelSize.height
        let origin = CGPoint(x: 0, y: y)

        newDateLabel.frame = CGRect(origin: origin, size: attributes.newDateLabelSize)
    }

    /// Positions the cell's bottom label.
    /// - attributes: The `MessagesCollectionViewLayoutAttributes` for the cell.
    func layoutSenderNameLabel(with attributes: MessageLayoutAttributes) {
        senderNameLabel.textAlignment = .natural
        senderNameLabel.textInsets = .zero

        let y = containerView.frame.maxY + attributes.containerPadding.bottom
        let origin = CGPoint(x: 0, y: y)

        senderNameLabel.frame = CGRect(origin: origin, size: attributes.senderNameLabelSize)
    }
}

