//
//  AccountSettingsViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import MessageUI
import TinodeSDK
import TinodiosDB
import UIKit

class AccountSettingsViewController: UITableViewController {

    @IBOutlet weak var topicTitleTextView: UITextView!
    @IBOutlet weak var avatarImage: RoundImageView!
    @IBOutlet weak var loadAvatarButton: UIButton!
    @IBOutlet weak var sendReadReceiptsSwitch: UISwitch!
    @IBOutlet weak var sendTypingNotificationsSwitch: UISwitch!
    @IBOutlet weak var myUIDLabel: UILabel!

    @IBOutlet weak var authUsersPermissions: UITableViewCell!
    @IBOutlet weak var anonUsersPermissions: UITableViewCell!
    @IBOutlet weak var authPermissionsLabel: UILabel!
    @IBOutlet weak var anonPermissionsLabel: UILabel!

    @IBOutlet weak var manageContacts: UITableViewCell!
    @IBOutlet weak var manageTags: UITableViewCell!

    @IBOutlet weak var actionChangePassword: UITableViewCell!
    @IBOutlet weak var actionLogOut: UITableViewCell!

    weak var tinode: Tinode!
    weak var me: DefaultMeTopic!
    private var imagePicker: ImagePicker!

    @IBOutlet weak var contactUs: UITableViewCell!
    @IBOutlet weak var termsOfUse: UITableViewCell!
    @IBOutlet weak var privacyPolicy: UITableViewCell!
    @IBOutlet weak var appVersion: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

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
            forView: authUsersPermissions,
            action: #selector(AccountSettingsViewController.permissionsTapped),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: anonUsersPermissions,
            action: #selector(AccountSettingsViewController.permissionsTapped),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: manageTags,
            action: #selector(AccountSettingsViewController.manageTagsClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: manageContacts,
            action: #selector(AccountSettingsViewController.addContactClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionChangePassword,
            action: #selector(AccountSettingsViewController.changePasswordClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionLogOut,
            action: #selector(AccountSettingsViewController.logoutClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: privacyPolicy,
            action: #selector(AccountSettingsViewController.privacyPolicyClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: contactUs,
            action: #selector(AccountSettingsViewController.contactUsClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: termsOfUse,
            action: #selector(AccountSettingsViewController.termsOfUseClicked),
            actionTarget: self)

        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: true)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let versionCode = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        self.appVersion.text = "\(version) (\(versionCode))"
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
        self.avatarImage.set(icon: me.pub?.photo?.image(), title: me.pub?.fn, id: self.tinode.myUid)
        self.avatarImage.letterTileFont = self.avatarImage.letterTileFont.withSize(CGFloat(50))
        // Permissions.
        self.authPermissionsLabel.text = me.defacs?.getAuth() ?? ""
        self.authPermissionsLabel.sizeToFit()
        self.anonPermissionsLabel.text = me.defacs?.getAnon() ?? ""
        self.anonPermissionsLabel.sizeToFit()
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
        if sender === authUsersPermissions {
            return (me.defacs?.auth, .updateAuth)
        }
        if sender === anonUsersPermissions {
            return (me.defacs?.anon, .updateAnon)
        }
        return (nil, nil)
    }
    @objc
    func permissionsTapped(sender: UITapGestureRecognizer) {
        guard let v = sender.view else {
            Cache.log.debug("AccountSettingsVC - permissions tap from no sender view... quitting")
            return
        }
        let (acs, changeTypeOptional) = getAcsAndPermissionsChangeType(for: v)
        guard let acsUnwrapped = acs, let changeType = changeTypeOptional else {
            Cache.log.debug("AccountSettingsVC - permissionsTapped: could not get acs")
            return
        }
        UiUtils.showPermissionsEditDialog(over: self, acs: acsUnwrapped, callback: { permissions in
            _ = try? UiUtils.handlePermissionsChange(onTopic: self.me, forUid: nil, changeType: changeType, newPermissions: permissions)?.then(
                onSuccess: { msg in
                    DispatchQueue.main.async { self.reloadData() }
                        return nil
                    }
            )
        }, disabledPermissions: "ODS")
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

    @objc func manageTagsClicked(sender: UITapGestureRecognizer) {
        UiUtils.presentManageTagsEditDialog(over: self, forTopic: self.me)
    }
    @objc func addContactClicked(sender: UIGestureRecognizer) {
        let alert = UIAlertController(title: "Add contact", message: "Enter email or phone number", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addTextField(configurationHandler: nil)
        alert.addAction(UIAlertAction(
            title: "OK", style: .default,
            handler: { action in
                if let cred = ValidatedCredential.parse(from: alert.textFields?.first?.text) {
                    let credMsg: Credential?
                    switch cred {
                    case .email(let emailStr):
                        credMsg = Credential(meth: Credential.kMethEmail, val: emailStr)
                    case .phoneNum(let phone):
                        credMsg = Credential(meth: Credential.kMethPhone, val: phone)
                    default:
                        credMsg = nil
                    }
                    if let credential = credMsg {
                        do {
                            try self.me.setMeta(
                                meta: MsgSetMeta(desc: nil, sub: nil, tags: nil, cred: credential))?.thenCatch(onFailure: UiUtils.ToastFailureHandler)
                        } catch {
                            DispatchQueue.main.async {
                                UiUtils.showToast(message: "Failed to add credential \(error.localizedDescription)")
                            }
                        }
                    }
                }
        }))
        self.present(alert, animated: true)
    }

    @objc func changePasswordClicked(sender: UITapGestureRecognizer) {
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

    @objc func logoutClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: nil, message: "Are you sure you want to log out?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: "OK", style: .default,
            handler: { action in
                self.logout()
            }))
        self.present(alert, animated: true)
    }

    @objc func termsOfUseClicked(sender: UITapGestureRecognizer) {
        UIApplication.shared.openURL(URL(string: "https://tinode.co/terms.html")!)
    }

    @objc func privacyPolicyClicked(sender: UITapGestureRecognizer) {
        UIApplication.shared.openURL(URL(string: "https://tinode.co/privacy.html")!)
    }

    @objc func contactUsClicked(sender: UITapGestureRecognizer) {
        if MFMailComposeViewController.canSendMail() {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = self
            mail.setToRecipients(["mailto:info@tinode.co"])
            present(mail, animated: true)
        } else {
            UiUtils.showToast(message: "Cannot send email: functionality not accessible.")
        }
    }

    private func updatePassword(with newPassword: String) {
        guard newPassword.count >= 4 else {
            DispatchQueue.main.async {
                UiUtils.showToast(message: "Password too short")
            }
            return
        }
        guard let userName = Utils.getSavedLoginUserName() else {
            DispatchQueue.main.async {
                UiUtils.showToast(message: "Login info missing...")
            }
            return
        }
        _ = try? tinode.updateAccountBasic(uid: nil, username: userName, password: newPassword)?.then(
            onSuccess: nil,
            onFailure: { err in
                DispatchQueue.main.async {
                    UiUtils.showToast(message: "Could not change password: \(err.localizedDescription))")
                }
                return nil
            })
    }
    private func updateTitle(newTitle: String?) {
        guard let newTitle = newTitle else { return }
        let pub = me.pub == nil ? VCard(fn: nil, avatar: nil as Data?) : me.pub!.copy()
        if pub.fn != newTitle {
            pub.fn = String(newTitle.prefix(UiUtils.kMaxTitleLength))
        }
        _ = try? UiUtils.setTopicData(forTopic: self.me, pub: pub, priv: nil)?.then(
            onSuccess: { msg in
                DispatchQueue.main.async { self.reloadData() }
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
    }
    private func logout() {
        Cache.log.info("AccountSettingsVC - logging out")
        UiUtils.logoutAndRouteToLoginVC()
    }
}

extension AccountSettingsViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?, mimeType: String?, fileName: String?) {
        guard let image = image?.resize(width: CGFloat(UiUtils.kAvatarSize), height: CGFloat(UiUtils.kAvatarSize), clip: true) else {
            print("No image specified or failed to resize - skipping")
            Cache.log.debug("AccountSettingsVC - No image specified or failed to resize, skipping")
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

extension AccountSettingsViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
        if let err = error {
            UiUtils.showToast(message: "Failed to send email: \(err.localizedDescription)")
        }
    }
}
