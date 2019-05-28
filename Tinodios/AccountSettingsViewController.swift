//
//  AccountSettingsViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class AccountSettingsViewController: UIViewController {

    @IBOutlet weak var topicTitleTextView: UITextView!
    @IBOutlet weak var avatarImage: RoundImageView!
    @IBOutlet weak var loadAvatarButton: UIButton!
    @IBOutlet weak var sendReadReceiptsSwitch: UISwitch!
    @IBOutlet weak var sendTypingNotificationsSwitch: UISwitch!
    @IBOutlet weak var myUIDLabel: UILabel!
    @IBOutlet weak var authUsersPermissionsLabel: UILabel!
    @IBOutlet weak var anonUsersPermissionsLabel: UILabel!
    weak var tinode: Tinode!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tinode = Cache.getTinode()
        setUpAndloadData()
    }

    private func setUpAndloadData() {
        if let me = self.tinode.getMeTopic() {
            self.topicTitleTextView.text = me.pub?.fn ?? "Unknown"
            let tap = UITapGestureRecognizer(target: self, action: #selector(AccountSettingsViewController.topicTitleTapped))
            topicTitleTextView.isUserInteractionEnabled = true
            topicTitleTextView.addGestureRecognizer(tap)

            let userDefaults = UserDefaults.standard
            self.sendReadReceiptsSwitch.setOn(
                userDefaults.bool(forKey: Utils.kTinodePrefReadReceipts),
                animated: false)
            self.sendTypingNotificationsSwitch.setOn(
                userDefaults.bool(forKey: Utils.kTinodePrefTypingNotifications),
                animated: false)
            self.myUIDLabel.text = self.tinode.myUid
            self.myUIDLabel.sizeToFit()

            if let avatar = me.pub?.photo?.image() {
                self.avatarImage.image = avatar
            }

            self.authUsersPermissionsLabel.text = me.defacs?.getAuth() ?? ""
            self.authUsersPermissionsLabel.sizeToFit()
            self.anonUsersPermissionsLabel.text = me.defacs?.getAnon() ?? ""
            self.anonUsersPermissionsLabel.sizeToFit()
        }
    }
    @objc
    func topicTitleTapped(sender:UITapGestureRecognizer) {
        let me = tinode.getMeTopic()
        let alert = UIAlertController(title: "Edit account name", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addTextField(configurationHandler: { textField in
            textField.placeholder = "Full name, e.g. John Doe"
            textField.text = me?.pub?.fn ?? ""
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default,
                                      handler: { action in
            if let name = alert.textFields?.first?.text {
                print("New name: \(name)")
            }
        }))
        self.present(alert, animated: true)
    }
    @IBAction func readReceiptsClicked(_ sender: Any) {
        UserDefaults.standard.set(self.sendReadReceiptsSwitch.isOn, forKey: Utils.kTinodePrefReadReceipts)
    }
    @IBAction func typingNotificationsClicked(_ sender: Any) {
        UserDefaults.standard.set(self.sendTypingNotificationsSwitch.isOn, forKey: Utils.kTinodePrefTypingNotifications)
    }
}
