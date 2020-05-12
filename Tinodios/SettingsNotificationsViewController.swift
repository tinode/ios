//
//  SettingsNotificationsViewController.swift
//  Tinodios
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import TinodeSDK
import UIKit

class SettingsNotificationsViewController: UITableViewController {
    @IBOutlet weak var incognitoModeSwitch: UISwitch!
    @IBOutlet weak var sendReadReceiptsSwitch: UISwitch!
    @IBOutlet weak var sendTypingNotificationsSwitch: UISwitch!

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
        self.me = Cache.getTinode().getMeTopic()!
    }

    private func reloadData() {
        // Read notifications and typing indicator checkboxes.
        let userDefaults = UserDefaults.standard

        self.incognitoModeSwitch.setOn(me.isMuted, animated: false)
        self.sendReadReceiptsSwitch.setOn(
            userDefaults.bool(forKey: Utils.kTinodePrefReadReceipts),
            animated: false)
        self.sendTypingNotificationsSwitch.setOn(
            userDefaults.bool(forKey: Utils.kTinodePrefTypingNotifications),
            animated: false)
    }

    @IBAction func incognitoModeClicked(_ sender: Any) {
        let isChecked = incognitoModeSwitch.isOn
        self.me.updateMuted(muted: isChecked).then(
            onSuccess: UiUtils.ToastSuccessHandler,
            onFailure: { err in
                self.incognitoModeSwitch.isOn = !isChecked
                return UiUtils.ToastFailureHandler(err: err)
            }).thenFinally({
                DispatchQueue.main.async { self.reloadData() }
            })
    }

    @IBAction func readReceiptsClicked(_ sender: Any) {
        UserDefaults.standard.set(self.sendReadReceiptsSwitch.isOn, forKey: Utils.kTinodePrefReadReceipts)
    }

    @IBAction func typingNotificationsClicked(_ sender: Any) {
        UserDefaults.standard.set(self.sendTypingNotificationsSwitch.isOn, forKey: Utils.kTinodePrefTypingNotifications)
    }
}
