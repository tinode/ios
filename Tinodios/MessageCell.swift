//
//  MessageCell.swift
//
//  Copyright © 2019-2022 Tinode. All rights reserved.
//

import MobileVLCKit
import UIKit
import TinodeSDK

/// A protocol used to detect events in the chat message.
protocol MessageCellDelegate: AnyObject {
    /// Long tap anywhere in massage cell.
    func didLongTap(in cell: MessageCell)
    /// Tap on the message bubble.
    func didTapMessage(in cell: MessageCell)
    /// Tap on message content.
    func didTapContent(in cell: MessageCell, url: URL?)
    /// Tap on avatar.
    func didTapAvatar(in cell: MessageCell)
    /// Tap outside of message.
    func didTapOutsideContent(in cell: MessageCell)
    /// Clicked on cancel upload.
    func didTapCancelUpload(in cell: MessageCell)
    /// Activated media player.
    func didActivateMedia(in cell: MessageCell, audioPlayer: VLCMediaPlayer)
    /// Activated media player.
    func didPauseMedia(in cell: MessageCell, audioPlayer: VLCMediaPlayer)
    /// Media playback reached the end of the record.
    func didEndMediaPlayback(in cell: MessageCell, audioPlayer: VLCMediaPlayer)
    /// Seek operation completed.
    func didSeekMedia(in cell: MessageCell, audioPlayer: VLCMediaPlayer, pos: Float)
}

// Optional date, avatar, sender name, message bubble: content, delivery marker, timestamp.
class MessageCell: UICollectionViewCell {

    var seqId: Int = 0
    var isDeleted: Bool = false

    // Player for audio messages.
    var audioPlayer: VLCMediaPlayer?
    // Which entity is configured in the player: entity key.
    var mediaEntityKey: Int?

    // MARK: - Initializers

    public override init(frame: CGRect) {
        super.init(frame: frame)
        if traitCollection.userInterfaceStyle == .dark {
            backgroundColor = .black
        } else {
            backgroundColor = .white
        }
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setupSubviews()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        if traitCollection.userInterfaceStyle == .dark {
            backgroundColor = .black
        } else {
            backgroundColor = .white
        }
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setupSubviews()
    }

    deinit {
        self.audioPlayer?.stop()
        self.audioPlayer = nil
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
        content.contentInsetAdjustmentBehavior = .never

        content.isScrollEnabled = false
        content.isUserInteractionEnabled = true
        content.isEditable = false
        content.isSelectable = true

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
    var deliveryMarker: UIImageView = {
        let view = UIImageView()
        view.contentMode = UIView.ContentMode.scaleAspectFit
        return view
    }()

    /// Message timestamp.
    var timestampLabel: PaddedLabel = {
        let label = PaddedLabel()
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        return label
    }()

    /// Edited marker.
    var editedMarker: PaddedLabel = {
        let label = PaddedLabel()
        label.font = UIFont.preferredFont(forTextStyle: .caption2).withTraits(traits: .traitItalic)
        label.textAlignment = .right
        label.adjustsFontSizeToFitWidth = true
        return label
    }()

    var progressView = ProgressView()

    /// The `MessageCellDelegate` for the cell.
    weak var delegate: MessageCellDelegate?

    func setupSubviews() {
        contentView.addSubview(newDateLabel)
        contentView.addSubview(senderNameLabel)
        contentView.addSubview(containerView)
        containerView.addSubview(content)
        containerView.addSubview(timestampLabel)
        containerView.addSubview(deliveryMarker)
        containerView.addSubview(editedMarker)
        contentView.addSubview(avatarView)
    }

    func showProgressBar() {
        containerView.addSubview(progressView)
        progressView.isHidden = false
        containerView.bringSubviewToFront(progressView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        content.text = nil
        content.attributedText = nil
        newDateLabel.text = nil
        senderNameLabel.text = nil
        timestampLabel.text = nil
        editedMarker.text = nil
        deliveryMarker.image = nil
        avatarView.image = nil
        progressView.isHidden = true

        isDeleted = false

        audioPlayer?.stop()
        audioPlayer = nil
        seqId = 0
        mediaEntityKey = nil
    }

    /// Handle tap gesture on contentView and its subviews.
    func handleTapGesture(_ gesture: UIGestureRecognizer) {
        if gesture.isKind(of: UILongPressGestureRecognizer.self) {
            delegate?.didLongTap(in: self)
            return
        }

        let touchLocation = gesture.location(in: self)

        switch true {
        case progressView.cancelButton.frame.contains(convert(touchLocation, to: progressView)):
            delegate?.didTapCancelUpload(in: self)
        case content.frame.contains(convert(touchLocation, to: containerView)):
            let url = content.getURLForTap(convert(touchLocation, to: content))
            delegate?.didTapContent(in: self, url: url)
        case containerView.frame.contains(touchLocation):
            delegate?.didTapMessage(in: self)
        case avatarView.frame.contains(touchLocation):
            delegate?.didTapAvatar(in: self)
        default:
            delegate?.didTapOutsideContent(in: self)
            break
        }
    }

    @objc func cancelUploadClicked(sender: UIButton!) {
        delegate?.didTapCancelUpload(in: self)
    }

    /// Handle long press gesture, return true when gestureRecognizer's touch point in `containerView`'s frame
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let touchPoint = gestureRecognizer.location(in: self)
        guard gestureRecognizer.isKind(of: UILongPressGestureRecognizer.self) else { return false }
        return containerView.frame.contains(touchPoint)
    }

    /// This is needed for the context menu to work correctly.
    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func resignFirstResponder() -> Bool {
        super.resignFirstResponder()
        return true
    }

    /// Highlights the cell by gradually changing its background color to a darker one and back.
    func highlightAnimated(withDuration duration: TimeInterval) {
        let halfDuration = 0.5 * duration
        UIView.animate(withDuration: halfDuration) {
            self.containerView.backgroundColor = self.containerView.backgroundColor?.darker()
        }
        UIView.animate(withDuration: halfDuration) {
            self.containerView.backgroundColor = self.containerView.backgroundColor?.lighter()
        }
    }
}
