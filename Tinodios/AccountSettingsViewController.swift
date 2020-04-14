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

    private static let kSectionPersonal = 0
    private static let kSectionNotifications = 1
    private static let kSectionTags = 2
    private static let kSectionContacts = 3
    private static let kSectionActions = 4
    private static let kSectionPermissions = 5
    private static let kSectionGeneral = 6

    @IBOutlet weak var topicTitleTextView: UITextView!
    @IBOutlet weak var avatarImage: RoundImageView!
    @IBOutlet weak var loadAvatarButton: UIButton!

    @IBOutlet weak var incognitoModeSwitch: UISwitch!
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
            action: #selector(AccountSettingsViewController.accountNameTapped),
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

        self.incognitoModeSwitch.setOn(me.isMuted, animated: false)
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

        self.manageTags.detailTextLabel?.text = me.tags?.joined(separator: ", ")
    }

    @objc
    func accountNameTapped(sender: UITapGestureRecognizer) {
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
            UiUtils.handlePermissionsChange(onTopic: self.me, forUid: nil, changeType: changeType, newPermissions: permissions)?.then(
                onSuccess: { msg in
                    DispatchQueue.main.async { self.reloadData() }
                        return nil
                }
            )
        }, disabledPermissions: "ODS")
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

    @IBAction func loadAvatarClicked(_ sender: Any) {
        imagePicker.present(from: self.view)
    }

    @objc func manageTagsClicked(sender: UITapGestureRecognizer) {
        UiUtils.presentManageTagsEditDialog(over: self, forTopic: self.me)
    }

    @objc func addContactClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: "Add contact", message: "Enter email or phone number", preferredStyle: .alert)
        alert.addTextField(configurationHandler: nil)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: "OK", style: .default,
            handler: { action in
                var success = false
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
                        success = true
                        self.me.setMeta(meta: MsgSetMeta(desc: nil, sub: nil, tags: nil, cred: credential)).then(
                            onSuccess: { [weak self] _ in
                                DispatchQueue.main.async {
                                    UiUtils.showToast(message: "Confirmaition message sent to \(credential.val!)", level: .info)
                                    if let count = self?.me.creds?.count {
                                        let indexPath = IndexPath(row: count, section: AccountSettingsViewController.kSectionContacts)
                                        self?.tableView.insertRows(at: [indexPath], with: .automatic)
                                    }
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                                    // Update tags
                                    self?.reloadData()
                                }
                                return nil
                            },
                            onFailure: UiUtils.ToastFailureHandler)
                    }
                }
                if !success {
                   DispatchQueue.main.async {
                       UiUtils.showToast(message: "Entered text is neither email nor phone number.")
                   }
                }
        }))
        self.present(alert, animated: true)
    }

    private func confirmCredentialClicked(meth: String, at indexPath: IndexPath) {
        let alert = UIAlertController(title: "Confirm contact", message: "Enter confirmation code sent to you by \(meth):", preferredStyle: .alert)
        alert.addTextField(configurationHandler: nil)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: "OK", style: .default,
            handler: { action in
                guard let code = alert.textFields?.first?.text else { return }
                self.me.confirmCred(meth: meth, response: code)
                    .thenApply { [weak self] _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                            self?.tableView.reloadRows(at: [indexPath], with: .automatic)
                        })
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: "Confirmed successfully", level: .info)
                            self?.reloadData()
                        }
                        return nil
                    }
                    .thenCatch(UiUtils.ToastFailureHandler)
        }))
        self.present(alert, animated: true)
    }

    @objc func changePasswordClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: "Change Password", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addTextField(configurationHandler: { textField in
            textField.placeholder = "Enter new password"
            textField.isSecureTextEntry = true

            let iconNames = ["eye-30", "invisible-30"]
            let frameRect = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(20), height: CGFloat(20))
            let container = UIView()
            container.frame = frameRect

            let passwordVisibility: [UIButton] = iconNames.map {
                let button = UIButton(type: .custom)
                button.setImage(UIImage(named: $0), for: .normal)
                button.frame = frameRect
                button.addTarget(self, action: #selector(self.passwordVisibilityChanged), for: .touchUpInside)
                return button
            }

            passwordVisibility[1].isHidden = true
            passwordVisibility.forEach { container.addSubview($0) }
            UiUtils.adjustPasswordVisibilitySwitchColor(for: passwordVisibility, setColor: .darkGray)
            textField.rightView = container
            textField.rightViewMode = .always
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

    @objc func passwordVisibilityChanged(_ sender: Any) {
        if let container = (sender as? UIButton)?.superview,
            let textField = container.superview as? UITextField {
            // Flip password switch visibility and show/hide password.
            textField.isSecureTextEntry = !textField.isSecureTextEntry
            for v in container.subviews {
                v.isHidden = !v.isHidden
            }
        }
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
        tinode.updateAccountBasic(uid: nil, username: userName, password: newPassword).then(
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
        UiUtils.setTopicData(forTopic: self.me, pub: pub, priv: nil)?.then(
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
        UiUtils.updateAvatar(forTopic: self.me, image: image)?.then(
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

extension AccountSettingsViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == AccountSettingsViewController.kSectionContacts {
            return me.creds == nil ? 1 : (me.creds?.count ?? 0) + 1
        }
        return super.tableView(tableView, numberOfRowsInSection: section)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section != AccountSettingsViewController.kSectionContacts {
            return super.tableView(tableView, cellForRowAt: indexPath)
        }

        if indexPath.row == 0 {
            // [Add another] button cell.
            return super.tableView(tableView, cellForRowAt: indexPath)
        }

        // Cells with contacts.
        let cell = tableView.dequeueReusableCell(withIdentifier: "defaultCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "defaultCell")

        let cred = me.creds![indexPath.row - 1]

        cell.textLabel?.text = cred.description
        cell.selectionStyle = .none
        cell.textLabel?.sizeToFit()

        if !cred.isDone {
            cell.detailTextLabel?.text = "confirm"
        } else {
            cell.detailTextLabel?.text = ""
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        if indexPath.section == AccountSettingsViewController.kSectionContacts && indexPath.row > 0 {
            return 0
        }
        return super.tableView(tableView, indentationLevelForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == AccountSettingsViewController.kSectionContacts && indexPath.row > 0 {
            return tableView.rowHeight
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    // Handle tap on a row with contact
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section != AccountSettingsViewController.kSectionContacts || indexPath.row == 0 {
            // Don't call super.tableView.
            return
        }

        tableView.deselectRow(at: indexPath, animated:  true)

        guard let cred = me.creds?[indexPath.row - 1], !cred.isDone, cred.meth != nil else { return }

        confirmCredentialClicked(meth: cred.meth!, at: indexPath)
    }

    // Enable swipe to delete credentials.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == AccountSettingsViewController.kSectionContacts && indexPath.row > 0
    }

    // Actual handling of swipes.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let cred = me.creds?[indexPath.row - 1] else { return }
            self.me.delCredential(cred).then(
                onSuccess: { [weak self] _ in
                    DispatchQueue.main.async {
                        tableView.deleteRows(at: [indexPath], with: .fade)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        // Update tags
                        self?.reloadData()
                    }
                    return nil
                },
                onFailure: { err in
                    UiUtils.ToastFailureHandler(err: err)
                    return nil
                })
        }
    }
}
