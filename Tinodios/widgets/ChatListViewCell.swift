//
//  ChatListTableViewCell.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class ChatListViewCell: UITableViewCell {

    @IBOutlet weak var icon: AvatarWithOnlineIndicator!
    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var subtitle: UILabel!
    @IBOutlet weak var unreadCount: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    public func fillFromTopic(topic: DefaultComTopic) {
        title.text = topic.pub?.fn ?? "Unknown or unnamed"
        title.sizeToFit()
        subtitle.text = topic.comment
        subtitle.sizeToFit()
        let unread = topic.unread
        if unread > 0 {
            unreadCount.text = unread > 9 ? "9+" : String(unread)
            unreadCount.isHidden = false
        } else {
            unreadCount.isHidden = true
        }

        // Avatar image
        icon.set(icon: topic.pub?.photo?.image(), title: topic.pub?.fn, id: topic.name, online: topic.online)
    }
}
