//
//  SignupViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import PhoneNumberKit
import TinodeSDK
import UIKit
import TinodiosDB

class SignupViewController: UITableViewController {
    // UI positions of the Contacts fields.
    private static let kSectionContacts = 3
    private static let kContactsEmail = 0
    private static let kContactsTel = 1

    @IBOutlet weak var avatarImageView: RoundImageView!
    @IBOutlet weak var loginTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var descriptionTextField: UITextField!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var telTextField: PhoneNumberTextField!
    @IBOutlet weak var signUpButton: UIButton!

    var imagePicker: ImagePicker!
    var avatarReceived: Bool = false

    // Required credential methods.
    private var credMethods: [String]?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Get required credential methods.
        self.signUpButton.isEnabled = false
        _ = try? Cache.tinode.connectDefault(inBackground: false)?.then(
            onSuccess: { _ in
                if let creds = Cache.tinode.getRequiredCredMethods(forAuthLevel: "auth") {
                    self.credMethods = creds
                }
                if self.credMethods?.isEmpty ?? true {
                    self.credMethods = [Credential.kMethEmail]
                }
                DispatchQueue.main.async { self.signUpButton.isEnabled = true }
                return nil
            },
            onFailure: { err in
                Cache.log.error("Error connecting to tinode %@", err.localizedDescription)
                DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("Service unavailable at this time. Please try again later.", comment: "Service unavailable")) }
                return nil
            }).thenFinally {
                DispatchQueue.main.async { self.tableView.reloadData() }
            }

        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: true)

        // Listen to text change events to clear the possible error from earlier attempt.
        loginTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        passwordTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        nameTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        emailTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        telTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        telTextField.withFlag = true
        telTextField.withPrefix = true
        telTextField.withExamplePlaceholder = true
        telTextField.withDefaultPickerUI = true
        passwordTextField.showSecureEntrySwitch()
        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Show only required credential fields.
        if indexPath.section == SignupViewController.kSectionContacts {
            let method = self.credMethods?.first
            if method == nil ||
                (indexPath.row == SignupViewController.kContactsEmail && method! != Credential.kMethEmail) ||
                (indexPath.row == SignupViewController.kContactsTel && method! != Credential.kMethPhone) {
                return CGFloat.leastNonzeroMagnitude
            }
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
    }

    @IBAction func addAvatarClicked(_ sender: Any) {
        // Get avatar image
        self.imagePicker.present(from: self.view)
    }

    @IBAction func signUpClicked(_ sender: Any) {
        let login = UiUtils.ensureDataInTextField(loginTextField)
        let pwd = UiUtils.ensureDataInTextField(passwordTextField)
        let name = UiUtils.ensureDataInTextField(nameTextField, maxLength: UiUtils.kMaxTitleLength)

        guard !login.isEmpty && !pwd.isEmpty && !name.isEmpty else { return }

        var isError = false
        var creds = [Credential]()
        self.credMethods?.forEach { method in
            switch method {
            case Credential.kMethEmail:
                let credential = UiUtils.ensureDataInTextField(emailTextField)
                guard !credential.isEmpty, case let .email(cred) = ValidatedCredential.parse(from: credential) else {
                    emailTextField.markAsError()
                    isError = true
                    return
                }
                creds.append(Credential(meth: method, val: cred))
            case Credential.kMethPhone:
                guard telTextField.isValidNumber else {
                    telTextField.markAsError()
                    isError = true
                    return
                }
                let cred = telTextField.phoneNumberKit.format(telTextField.phoneNumber!, toType: .e164)
                creds.append(Credential(meth: method, val: cred))
            default:
                break
            }
        }
        guard !isError else { return }

        func doSignUp(withPublicCard pub: TheCard, withCredentials creds: [Credential]) {
            let desc = MetaSetDesc<TheCard, String>(pub: pub, priv: nil)
            desc.attachments = pub.photoRefs

            UiUtils.toggleProgressOverlay(in: self, visible: true, title: NSLocalizedString("Registering...", comment: "Progress overlay"))

            do {
                try Cache.tinode.connectDefault(inBackground: false)?
                    .thenApply { _ in
                        return Cache.tinode.createAccountBasic(uname: login, pwd: pwd, login: true, tags: nil, desc: desc, creds: creds)
                    }
                    .thenApply { [weak self] msg in
                        let tinode = Cache.tinode
                        SharedUtils.saveAuthToken(for: login, token: tinode.authToken, expires: tinode.authTokenExpires)
                        if let ctrl = msg?.ctrl, ctrl.code >= 300, ctrl.text.contains("validate credentials") {
                            DispatchQueue.main.async {
                                UiUtils.routeToCredentialsVC(in: self!.navigationController, verifying: ctrl.getStringArray(for: "cred")?.first)
                            }
                        } else {
                            if let token = Cache.tinode.authToken {
                                Cache.tinode.setAutoLoginWithToken(token: token)
                            }
                            UiUtils.routeToChatListVC()
                        }
                        return nil
                    }
                    .thenCatch { err in
                        Cache.log.error("Failed to create account: %@", err.localizedDescription)
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: String(format: NSLocalizedString("Failed to create account: %@", comment: "Error message"), err.localizedDescription))
                        }
                        Cache.tinode.disconnect()
                        return nil
                    }
                    .thenFinally { [weak self] in
                        guard let signupVC = self else { return }
                        DispatchQueue.main.async {
                            signupVC.signUpButton.isUserInteractionEnabled = true
                            UiUtils.toggleProgressOverlay(in: signupVC, visible: false)
                        }
                    }
            } catch {
                Cache.tinode.disconnect()
                DispatchQueue.main.async {
                    UiUtils.showToast(message: String(format: NSLocalizedString("Failed to create account: %@", comment: "Error message"), error.localizedDescription))
                    self.signUpButton.isUserInteractionEnabled = true
                    UiUtils.toggleProgressOverlay(in: self, visible: false)
                }
            }
        }

        signUpButton.isUserInteractionEnabled = false

        var avatar = avatarReceived ? avatarImageView?.image?.resize(width: UiUtils.kMaxAvatarSize, height: UiUtils.kMaxAvatarSize, clip: true) : nil
        if avatar != nil && (avatar!.size.width < UiUtils.kMinAvatarSize || avatar!.size.height < UiUtils.kMinAvatarSize) {
            avatar = nil
        }

        var description: String?
        if let desc = self.descriptionTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
            description = String(desc.prefix(UiUtils.kMaxTopicDdescriptionLength))
        }
        if let imageBits = avatar?.pixelData(forMimeType: Photo.kDefaultType) {
            if imageBits.count > UiUtils.kMaxInbandAvatarBytes {
                // Sending image out of band.
                Cache.getLargeFileHelper().startAvatarUpload(mimetype: Photo.kDefaultType, data: imageBits, topicId: "newacc", completionCallback: {(srvmsg, error) in
                    guard let error = error else {
                        let thumbnail = avatar!.resize(width: UiUtils.kAvatarPreviewDimensions, height: UiUtils.kAvatarPreviewDimensions, clip: true)
                        let photo = Photo(data: thumbnail?.pixelData(forMimeType: Photo.kDefaultType), ref: srvmsg?.ctrl?.getStringParam(for: "url"), width: Int(avatar!.size.width), height: Int(avatar!.size.height))
                        doSignUp(withPublicCard: TheCard(fn: name, avatar: photo, note: description), withCredentials: creds)
                        return
                    }
                    UiUtils.ToastFailureHandler(err: error)
                })
                return
            }
        }

        doSignUp(withPublicCard: TheCard(fn: name, avatar: avatar, note: description), withCredentials: creds)
    }
}

extension SignupViewController: ImagePickerDelegate {
    func didSelect(media: ImagePickerMediaType?) {
        guard case .image(let image, _, _) = media,
            let image = image?.resize(width: CGFloat(UiUtils.kMaxAvatarSize), height: CGFloat(UiUtils.kMaxAvatarSize), clip: true) else { return }

        self.avatarImageView.image = image
        avatarReceived = true
    }
}
