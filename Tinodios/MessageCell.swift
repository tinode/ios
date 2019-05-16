//
//  MessageCell.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

/// A protocol used to detect taps in the chat message.
protocol MessageCellDelegate: class {
    /// Tap on the message bubble
    func didTapMessage(in cell: MessageCell)
    /// Tap on message content
    func didTapContent(in cell: MessageCell, url: URL?)
    /// Tap on avatar
    func didTapAvatar(in cell: MessageCell)
}

// Contains message bubble + avatar + delivery markers.
class MessageCell: UICollectionViewCell, UITextViewDelegate {

    // MARK: - Initializers

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setupSubviews()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        backgroundColor = UIColor.white
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setupSubviews()
    }

    /// The image view with the avatar.
    var avatarView: RoundImageView = RoundImageView()

    /// The UIImageView with background being the bubble,
    /// holds the message's content view.
    var containerView: UIImageView = {
        let view = UIImageView()
        view.clipsToBounds = true
        view.layer.masksToBounds = true
        return view
    }()

    /// The message content
    var content: RichTextView = {
        let content = RichTextView()
        content.isUserInteractionEnabled = true
        if #available(iOS 11.0, *) {
            content.contentInsetAdjustmentBehavior = .never
        }

        return content
    }()

    /// The label above the messageBubble which holds the date of conversation.
    var newDateLabel: PaddedLabel = {
        let label = PaddedLabel()
        label.textAlignment = .center
        return label
    }()

    /// The label under the messageBubble: sender's name in group topics.
    var senderNameLabel: PaddedLabel = {
        let label = PaddedLabel()
        label.textAlignment = .natural
        return label
    }()

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
        content.delegate = self
        containerView.addSubview(content)
        // containerView.addSubview(deliveryMarker)
        // containerView.addSubview(timestampLabel)
        contentView.addSubview(avatarView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        content.attributedText = nil
        newDateLabel.text = nil
        senderNameLabel.text = nil
        timestampLabel.text = nil
        deliveryMarker.image = nil
        avatarView.image = nil
    }

    /// Handle tap gesture on contentView and its subviews.
    func handleTapGesture(_ gesture: UIGestureRecognizer) {
        let touchLocation = gesture.location(in: self)

        switch true {
        case content.frame.contains(convert(touchLocation, to: content)):
            // let url = content.getURLForTap(convert(touchLocation, to: content))
            //delegate?.didTapContent(in: self, url: url)
            break
        case containerView.frame.contains(touchLocation):
            delegate?.didTapMessage(in: self)
        case avatarView.frame.contains(touchLocation):
            delegate?.didTapAvatar(in: self)
        default:
            break
        }
    }

    /// Handle long press gesture, return true when gestureRecognizer's touch point in `containerView`'s frame
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let touchPoint = gestureRecognizer.location(in: self)
        guard gestureRecognizer.isKind(of: UILongPressGestureRecognizer.self) else { return false }
        return containerView.frame.contains(touchPoint)
    }

    func textView(_ content: UITextView, shouldInteractWith: NSTextAttachment, in: NSRange, interaction: UITextItemInteraction) -> Bool {
        print("shouldInteractWith attachment \(shouldInteractWith)")
        return true
    }

    func textView(_ content: UITextView, shouldInteractWith: URL, in: NSRange, interaction: UITextItemInteraction) -> Bool {
        print("shouldInteractWith URL \(shouldInteractWith)")
        return true
    }
}

