//
//  SettingsPersonalViewController.swift
//  Tinodios
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import TinodeSDK
import UIKit

class SettingsPersonalViewController: UITableViewController {

    private static let kSectionPersonal = 0
    private static let kSectionContacts = 1
    private static let kSectionTags = 2

    @IBOutlet weak var userNameLabel: UILabel!
    @IBOutlet weak var avatarImage: RoundImageView!
    @IBOutlet weak var loadAvatarButton: UIButton!

    @IBOutlet weak var myUIDLabel: UILabel!

    @IBOutlet weak var manageContacts: UITableViewCell!
    @IBOutlet weak var manageTags: UITableViewCell!

    weak var tinode: Tinode!
    weak var me: DefaultMeTopic!
    private var imagePicker: ImagePicker!

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

        UiUtils.setupTapRecognizer(
            forView: userNameLabel,
            action: #selector(SettingsPersonalViewController.userNameTapped),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: manageTags,
            action: #selector(SettingsPersonalViewController.manageTagsClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: manageContacts,
            action: #selector(SettingsPersonalViewController.addContactClicked),
            actionTarget: self)

        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: true)
    }

    private func reloadData() {
        // Title.
        self.userNameLabel.text = me.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")

        // My UID/Address label.
        self.myUIDLabel.text = self.tinode.myUid
        self.myUIDLabel.sizeToFit()

        // Avatar.
        self.avatarImage.set(icon: me.pub?.photo?.image(), title: me.pub?.fn, id: self.tinode.myUid)
        self.avatarImage.letterTileFont = self.avatarImage.letterTileFont.withSize(CGFloat(50))

        self.manageTags.detailTextLabel?.text = me.tags?.joined(separator: ", ")

        // Note: tableView.reloadSections() would be better but
        // it makes the [Add another] contact button disappear.
        // Likely due to this: https://stackoverflow.com/questions/3132135/initally-visible-cells-gets-invisible-after-calling-reloadsectionswithrowanimat
        self.tableView.reloadData()
    }

    @IBAction func loadAvatarClicked(_ sender: Any) {
        imagePicker.present(from: self.view)
    }

    @objc
    func userNameTapped(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("Edit account name", comment: "Alert title"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addTextField(configurationHandler: { textField in
            textField.placeholder = NSLocalizedString("Full name, e.g. John Doe", comment: "User name prompt")
            textField.text = self.me?.pub?.fn ?? ""
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert action"), style: .default,
                                      handler: { action in
            if let name = alert.textFields?.first?.text {
                self.updateUserName(name)
            }
        }))
        self.present(alert, animated: true)
    }

    @objc func manageTagsClicked(sender: UITapGestureRecognizer) {
        UiUtils.presentManageTagsEditDialog(over: self, forTopic: self.me)
    }

    @objc func addContactClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("Add contact", comment: "Alert title"), message: NSLocalizedString("Enter email or phone number", comment: "Alert message"), preferredStyle: .alert)
        alert.addTextField(configurationHandler: nil)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: ""), style: .default,
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
                        let oldCount = self.me.creds?.count ?? 0
                        self.me.setMeta(meta: MsgSetMeta(desc: nil, sub: nil, tags: nil, cred: credential)).then(
                            onSuccess: { [weak self] _ in
                                DispatchQueue.main.async {
                                    UiUtils.showToast(message: String(format: NSLocalizedString("Confirmaition message sent to %@", comment: "Info message"), credential.val!), level: .info)
                                    if let count = self?.me.creds?.count, count > oldCount {
                                        let indexPath = IndexPath(row: count, section: SettingsPersonalViewController.kSectionContacts)
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
                    UiUtils.showToast(message: NSLocalizedString("Entered text is neither email nor phone number.", comment: "Error message"))
                }
        }))
        self.present(alert, animated: true)
    }

    private func confirmCredentialClicked(meth: String, at indexPath: IndexPath) {
        let alert = UIAlertController(title: NSLocalizedString("Confirm contact", comment: "Alert title"), message: String(format: NSLocalizedString("Enter confirmation code sent to you by %@", comment: "Alert prompt"), meth), preferredStyle: .alert)
        alert.addTextField(configurationHandler: nil)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: ""), style: .default,
            handler: { action in
                guard let code = alert.textFields?.first?.text else { return }
                self.me.confirmCred(meth: meth, response: code)
                    .thenApply { [weak self] _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                            self?.tableView.reloadRows(at: [indexPath], with: .automatic)
                        })
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: NSLocalizedString("Confirmed successfully", comment: "Toast info message"), level: .info)
                            self?.reloadData()
                        }
                        return nil
                    }
                    .thenCatch(UiUtils.ToastFailureHandler)
        }))
        self.present(alert, animated: true)
    }

    private func updateUserName(_ userName: String?) {
        guard let userName = userName else { return }
        let pub = me.pub == nil ? VCard(fn: nil, avatar: nil as Data?) : me.pub!.copy()
        if pub.fn != userName {
            pub.fn = String(userName.prefix(UiUtils.kMaxTitleLength))
        }
        UiUtils.setTopicData(forTopic: self.me, pub: pub, priv: nil)?.then(
            onSuccess: { msg in
                DispatchQueue.main.async { self.reloadData() }
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
    }
}

extension SettingsPersonalViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?, mimeType: String?, fileName: String?) {
        guard let image = image?.resize(width: CGFloat(UiUtils.kAvatarSize), height: CGFloat(UiUtils.kAvatarSize), clip: true) else {
            Cache.log.debug("SettingsPersonalVC - No image specified or failed to resize, skipping")
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

extension SettingsPersonalViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == SettingsPersonalViewController.kSectionContacts {
            return me.creds == nil ? 1 : (me.creds?.count ?? 0) + 1
        }
        return super.tableView(tableView, numberOfRowsInSection: section)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == SettingsPersonalViewController.kSectionContacts else {
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
            cell.detailTextLabel?.text = NSLocalizedString("confirm", comment: "Button text")
        } else {
            cell.detailTextLabel?.text = ""
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        if indexPath.section == SettingsPersonalViewController.kSectionContacts && indexPath.row > 0 {
            return 0
        }
        return super.tableView(tableView, indentationLevelForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == SettingsPersonalViewController.kSectionContacts && indexPath.row > 0 {
            return tableView.rowHeight
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    // Handle tap on a row with contact
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section != SettingsPersonalViewController.kSectionContacts || indexPath.row == 0 {
            // Don't call super.tableView.
            return
        }

        tableView.deselectRow(at: indexPath, animated:  true)

        guard let cred = me.creds?[indexPath.row - 1], !cred.isDone, cred.meth != nil else { return }

        confirmCredentialClicked(meth: cred.meth!, at: indexPath)
    }

    // Enable swipe to delete credentials.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == SettingsPersonalViewController.kSectionContacts && indexPath.row > 0
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
                onFailure: UiUtils.ToastFailureHandler)
        }
    }
}

