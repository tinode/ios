//
//  SettingsNotificationsViewController.swift
//  Tinodios
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import TinodeSDK
import TinodiosDB
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
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        reloadData()
    }

    private func setup() {
        self.me = Cache.tinode.getMeTopic()!
    }

    private func reloadData() {
        // Read notifications and typing indicator checkboxes.
        self.incognitoModeSwitch.setOn(me.isMuted, animated: false)
        self.sendReadReceiptsSwitch.setOn(
            SharedUtils.kAppDefaults.bool(forKey: SharedUtils.kTinodePrefReadReceipts),
            animated: false)
        self.sendTypingNotificationsSwitch.setOn(
            SharedUtils.kAppDefaults.bool(forKey: SharedUtils.kTinodePrefTypingNotifications),
            animated: false)
    }

    @IBAction func incognitoModeClicked(_ sender: Any) {
        let isChecked = incognitoModeSwitch.isOn
        self.me.updateMuted(muted: isChecked).then(
            onSuccess: UiUtils.ToastSuccessHandler,
            onFailure: { err in
                DispatchQueue.main.async { self.incognitoModeSwitch.isOn = !isChecked }
                return UiUtils.ToastFailureHandler(err: err)
            }).thenFinally({
                DispatchQueue.main.async { self.reloadData() }
            })
    }

    @IBAction func readReceiptsClicked(_ sender: Any) {
        SharedUtils.kAppDefaults.set(self.sendReadReceiptsSwitch.isOn, forKey: SharedUtils.kTinodePrefReadReceipts)
    }

    @IBAction func typingNotificationsClicked(_ sender: Any) {
        SharedUtils.kAppDefaults.set(self.sendTypingNotificationsSwitch.isOn, forKey: SharedUtils.kTinodePrefTypingNotifications)
    }
}
