//
//  AccountSettingsViewController.swift
//
//  Copyright © 2019-2025 Tinode LLC. All rights reserved.
//

import TinodeSDK
import UIKit

class AccountSettingsViewController: UITableViewController {
    private static let kSectionBasic = 0
    // Avatar = 0
    // Name = 1
    private static let kSectionPersonal = 1
    // MyUID = 0
    private static let kPersonalAlias = 1
    private static let kPersonalVerified = 2
    private static let kPersonalStaff = 3
    private static let kPersonalDanger = 4
    private static let kPersonalDescription = 5

    @IBOutlet weak var avatarImageView: RoundImageView!
    @IBOutlet weak var userNameLabel: UILabel!
    @IBOutlet weak var myUIDLabel: UILabel!
    @IBOutlet weak var aliasLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    
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

        self.descriptionLabel.text = me.pub?.note ?? me.tags?.joined(separator: ", ")

        // My UID/Address label.
        self.myUIDLabel.text = self.tinode.myUid
        self.myUIDLabel.sizeToFit()

        self.aliasLabel.text = "@\(me.alias ?? "")"
        self.aliasLabel.sizeToFit()
    }

    @IBAction func copyTopicValue(_ sender: UIButton) {
        UIPasteboard.general.string = sender.tag == 0 ? self.tinode.myUid : me.alias
        UiUtils.showToast(message: sender.tag == 0 ?
                            NSLocalizedString("Address copied", comment: "Toast notification") :
                            NSLocalizedString("Alias copied", comment: "Toast notification"),
                          level: .info)
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == AccountSettingsViewController.kSectionPersonal {
            if (indexPath.row == AccountSettingsViewController.kPersonalAlias && (me.alias ?? "").isEmpty) ||
                (indexPath.row == AccountSettingsViewController.kPersonalVerified && !me.isVerified) ||
                (indexPath.row == AccountSettingsViewController.kPersonalStaff && !me.isStaffManaged) ||
                (indexPath.row == AccountSettingsViewController.kPersonalDanger && !me.isDangerous) {
                return CGFloat.leastNonzeroMagnitude
            }
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        if indexPath.section == AccountSettingsViewController.kSectionBasic {
            // Hide separator lines in the top sections.
            cell.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: UIScreen.main.bounds.width)
        }
        return cell
    }
}
