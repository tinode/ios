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
    weak var me: DefaultMeTopic!
    private var imagePicker: ImagePicker!

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    override func viewWillAppear(_ animated: Bool) {
        reloadData()
    }
    private func setup() {
        self.tinode = Cache.getTinode()
        self.me = self.tinode.getMeTopic()!

        UiUtils.setupTapRecognizer(
            forView: topicTitleTextView,
            action: #selector(AccountSettingsViewController.topicTitleTapped),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: authUsersPermissionsLabel,
            action: #selector(AccountSettingsViewController.permissionsTapped),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: anonUsersPermissionsLabel,
            action: #selector(AccountSettingsViewController.permissionsTapped),
            actionTarget: self)
        self.imagePicker = ImagePicker(
            presentationController: self, delegate: self)
    }
    private func reloadData() {
        // Title.
        self.topicTitleTextView.text = me.pub?.fn ?? "Unknown"
        // Read notifications and typing indicator checkboxes.
        let userDefaults = UserDefaults.standard
        self.sendReadReceiptsSwitch.setOn(
            userDefaults.bool(forKey: Utils.kTinodePrefReadReceipts),
            animated: false)
        self.sendTypingNotificationsSwitch.setOn(
            userDefaults.bool(forKey: Utils.kTinodePrefTypingNotifications),
            animated: false)
        // My UID/Address label.
        self.myUIDLabel.text = self.tinode.myUid
        self.myUIDLabel.sizeToFit()
        // Avatar.
        if let avatar = me.pub?.photo?.image() {
            self.avatarImage.image = avatar
        }
        // Permissions.
        self.authUsersPermissionsLabel.text = me.defacs?.getAuth() ?? ""
        self.authUsersPermissionsLabel.sizeToFit()
        self.anonUsersPermissionsLabel.text = me.defacs?.getAnon() ?? ""
        self.anonUsersPermissionsLabel.sizeToFit()
    }
    @objc
    func topicTitleTapped(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: "Edit account name", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addTextField(configurationHandler: { textField in
            textField.placeholder = "Full name, e.g. John Doe"
            textField.text = self.me?.pub?.fn ?? ""
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default,
                                      handler: { action in
            if let name = alert.textFields?.first?.text {
                self.updateTitle(newTitle: name)
            }
        }))
        self.present(alert, animated: true)
    }
    private func getAcsAndPermissionsChangeType(for sender: UIView) -> (AcsHelper?, UiUtils.PermissionsChangeType?) {
        if sender === authUsersPermissionsLabel {
            return (me.defacs?.auth, .updateAuth)
        }
        if sender === anonUsersPermissionsLabel {
            return (me.defacs?.anon, .updateAnon)
        }
        return (nil, nil)
    }
    @objc
    func permissionsTapped(sender: UITapGestureRecognizer) {
        guard let v = sender.view else {
            print("Tap from no sender view... quitting")
            return
        }
        let (acs, changeTypeOptional) = getAcsAndPermissionsChangeType(for: v)
        guard let acsUnwrapped = acs, let changeType = changeTypeOptional else {
            print("could not get acs")
            return
        }
        UiUtils.showPermissionsEditDialog(
            over: self, acs: acsUnwrapped,
            callback: {
                permissionsTuple in
                _ = try? UiUtils.handlePermissionsChange(
                    onTopic: self.me, forUid: nil, changeType: changeType,
                    permissions: permissionsTuple)?.then(
                        onSuccess: { msg in
                            DispatchQueue.main.async { self.reloadData() }
                            return nil
                        }
                    )},
            disabledPermissions: nil)
    }
    @IBAction func readReceiptsClicked(_ sender: Any) {
        UserDefaults.standard.set(self.sendReadReceiptsSwitch.isOn, forKey: Utils.kTinodePrefReadReceipts)
    }
    @IBAction func typingNotificationsClicked(_ sender: Any) {
        UserDefaults.standard.set(self.sendTypingNotificationsSwitch.isOn, forKey: Utils.kTinodePrefTypingNotifications)
    }
    @IBAction func loadAvatarClicked(_ sender: Any) {
        imagePicker.present(from: self.view)
    }
    @IBAction func changePasswordClicked(_ sender: Any) {
        let alert = UIAlertController(title: "Change Password", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addTextField(configurationHandler: { textField in
            textField.placeholder = "Enter new password"
            textField.isSecureTextEntry = true
        })
        alert.addAction(UIAlertAction(
            title: "OK", style: .default,
            handler: { action in
                if let newPassword = alert.textFields?.first?.text {
                    self.updatePassword(with: newPassword)
                }
            }))
        self.present(alert, animated: true)
    }
    @IBAction func logoutClicked(_ sender: Any) {
        let alert = UIAlertController(title: nil, message: "Are you sure you want to log out?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: "OK", style: .default,
            handler: { action in
                self.logout()
            }))
        self.present(alert, animated: true)
    }
    private func updatePassword(with newPassword: String) {
        guard newPassword.count >= 4 else {
            DispatchQueue.main.async {
                UiUtils.showToast(message: "Password too short")
            }
            return
        }
        guard let userName = UserDefaults.standard.string(forKey: Utils.kTinodePrefLastLogin) else {
            DispatchQueue.main.async {
                UiUtils.showToast(message: "Login info missing...")
            }
            return
        }
        try? tinode.updateAccountBasic(uid: nil, username: userName, password: newPassword)?.then(
            onSuccess: nil,
            onFailure: { err in
                DispatchQueue.main.async {
                    UiUtils.showToast(message: "Could not change password: \(err.localizedDescription)")
                }
                return nil
            })
    }
    private func updateTitle(newTitle: String?) {
        guard let newTitle = newTitle else { return }
        let pub = me.pub == nil ? VCard(fn: nil, avatar: nil as Data?) : me.pub!.copy()
        if pub.fn != newTitle {
            pub.fn = newTitle
        }
        UiUtils.setTopicData(forTopic: self.me, pub: pub, priv: nil)
    }
    private func logout() {
        print("logging out")
        BaseDb.getInstance().logout()
        Cache.invalidate()
        UiUtils.routeToLoginVC()
    }
}

extension AccountSettingsViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?) {
        guard let image = image else {
            print("No image specified - skipping")
            return
        }
        _ = try? UiUtils.updateAvatar(forTopic: self.me, image: image)?.then(
            onSuccess: { msg in
                DispatchQueue.main.async {
                    self.reloadData()
                }
                return nil
            })
    }
}
