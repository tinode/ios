//
//  AccountSettingsViewController.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import TinodeSDK
import UIKit

class AccountSettingsViewController: UITableViewController {
    private static let kSectionPersonal = 0
    private static let kPersonalVerified = 2
    private static let kPersonalStaff = 3
    private static let kPersonalDanger = 4

    @IBOutlet weak var avatarImageView: RoundImageView!
    @IBOutlet weak var userNameLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var myUIDLabel: UILabel!

    weak var tinode: Tinode!
    weak var me: DefaultMeTopic!

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadData()
    }

    private func setup() {
        self.tinode = Cache.tinode
        self.me = self.tinode.getMeTopic()!
    }

    private func reloadData() {
        // Title.
        self.userNameLabel.text = me.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")

        // Avatar.
        self.avatarImageView.set(pub: me.pub, id: self.tinode.myUid, deleted: false)
        self.avatarImageView.letterTileFont = self.avatarImageView.letterTileFont.withSize(CGFloat(50))

        self.subtitleLabel.text = me.pub?.note ?? me.tags?.joined(separator: ", ")

        // My UID/Address label.
        self.myUIDLabel.text = self.tinode.myUid
        self.myUIDLabel.sizeToFit()
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == AccountSettingsViewController.kSectionPersonal {
            if (indexPath.row == AccountSettingsViewController.kPersonalVerified && !me.isVerified) ||
                (indexPath.row == AccountSettingsViewController.kPersonalStaff && !me.isStaffManaged) ||
                (indexPath.row == AccountSettingsViewController.kPersonalDanger && !me.isDangerous) {
                return CGFloat.leastNonzeroMagnitude
            }
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }
}
