//
//  ChatListTableViewCell.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

class ChatListViewCell: UITableViewCell {
    private static let kIconWidth: CGFloat = 18
    private static let kMessageStatusWidth: CGFloat = 14
    private static let kIconSeparator: CGFloat = 4

    @IBOutlet weak var icon: AvatarWithOnlineIndicator!
    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var subtitle: UILabel!
    @IBOutlet weak var unreadCount: UILabel!
    @IBOutlet weak var iconBlocked: UIImageView!
    @IBOutlet weak var iconMuted: UIImageView!
    @IBOutlet weak var iconBlockedWidth: NSLayoutConstraint!
    @IBOutlet weak var unreadCountWidth: NSLayoutConstraint!
    @IBOutlet weak var channelIndicator: UIImageView!
    @IBOutlet weak var channelIndicatorWidth: NSLayoutConstraint!
    @IBOutlet weak var iconMessageStatus: UIImageView!
    @IBOutlet weak var iconMessageStatusWidth: NSLayoutConstraint!

    override func awakeFromNib() {
        super.awakeFromNib()
        iconMuted.tintColor = UIColor.init(fromHexCode: 0xFFCCCCCC)
        iconBlocked.tintColor = iconMuted.tintColor
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }

    private func setMessageStatusVisibility(hidden: Bool) {
        let width: CGFloat = hidden ? 0 : ChatListViewCell.kMessageStatusWidth
        iconMessageStatus.isHidden = hidden
        iconMessageStatusWidth.constant = width
    }

    public func fillFromTopic(topic: DefaultComTopic) {
        title.text = topic.pub?.fn ?? "Unknown or unnamed"
        title.sizeToFit()
        if let msg = topic.latestMessage as? StoredMessage, msg.getSeq == topic.seq {
            // If we have a latestMessage and its up to date.
            subtitle.attributedText = msg.attributedPreview(fitIn: subtitle.frame.size)
            if msg.from == Cache.tinode.myUid {
                setMessageStatusVisibility(hidden: false)
                let (image, tint) = UiUtils.deliveryMarkerIcon(for: msg, in: topic)
                iconMessageStatus.image = image
                iconMessageStatus.tintColor = tint
            } else {
                setMessageStatusVisibility(hidden: true)
            }
        } else {
            subtitle.text = topic.comment
            setMessageStatusVisibility(hidden: true)
        }
        subtitle.sizeToFit()
        if topic.isChannel {
            channelIndicator.isHidden = false
            channelIndicatorWidth.constant = ChatListViewCell.kIconWidth
        } else {
            channelIndicator.isHidden = true
            channelIndicatorWidth.constant = .leastNonzeroMagnitude
        }

        let unread = topic.unread
        if unread > 0 {
            unreadCount.text = unread > 9 ? "9+" : String(unread)
            unreadCount.isHidden = false
            unreadCountWidth.constant = ChatListViewCell.kIconWidth
        } else {
            unreadCount.isHidden = true
            unreadCountWidth.constant = .leastNonzeroMagnitude
        }

        iconBlocked.isHidden = !topic.isJoiner
        iconBlockedWidth.constant = topic.isJoiner ? .leastNonzeroMagnitude : ChatListViewCell.kIconWidth + ChatListViewCell.kIconSeparator * 2

        iconMuted.isHidden = !topic.isMuted

        // Avatar image
        icon.set(icon: topic.pub?.photo?.image(), title: topic.pub?.fn, id: topic.name, online: topic.isChannel ? nil : topic.online)
    }
}
