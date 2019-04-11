//
//  ChatListTableViewCell.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import MessageKit

class ChatListTableViewCell: UITableViewCell {

    @IBOutlet weak var icon: AvatarView!
    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var subtitle: UILabel!

    @IBOutlet weak var unreadCount: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }

}
