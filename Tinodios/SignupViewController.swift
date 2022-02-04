//
//  SignupViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class SignupViewController: UITableViewController {

    @IBOutlet weak var avatarImageView: RoundImageView!
    @IBOutlet weak var loginTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var emailPhoneTextField: UITextField!
    @IBOutlet weak var signUpButton: UIButton!
    @IBOutlet var passwordVisibility: [UIButton]!

    private var passwordVisible: Bool = false
    var imagePicker: ImagePicker!
    var avatarReceived: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        UiUtils.adjustPasswordVisibilitySwitchColor(for: passwordVisibility, setColor: .darkGray)

        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: true)

        // Listen to text change events to clear the possible error from earlier attempt.
        loginTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        passwordTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        nameTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        emailPhoneTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        UiUtils.clearTextFieldError(textField)
    }

    @IBAction func addAvatarClicked(_ sender: Any) {
        // Get avatar image
        self.imagePicker.present(from: self.view)
    }

    @IBAction func passwordVisibilityChanged(_ sender: Any) {
        passwordTextField.isSecureTextEntry = passwordVisible
        passwordVisible = !passwordVisible
        for v in passwordVisibility {
            v.isHidden = !v.isHidden
        }
    }

    @IBAction func signUpClicked(_ sender: Any) {
        let login = UiUtils.ensureDataInTextField(loginTextField)
        let pwd = UiUtils.ensureDataInTextField(passwordTextField)
        let name = UiUtils.ensureDataInTextField(nameTextField, maxLength: UiUtils.kMaxTitleLength)
        let credential = UiUtils.ensureDataInTextField(emailPhoneTextField)

        guard !login.isEmpty && !pwd.isEmpty && !name.isEmpty && !credential.isEmpty else { return }

        var method: String?
        if let cred = ValidatedCredential.parse(from: credential) {
            switch cred {
            case .email:
                method = Credential.kMethEmail
            case .phoneNum:
                method = Credential.kMethPhone
            default:
                break
            }
        }

        guard method != nil else {
            UiUtils.markTextFieldAsError(emailPhoneTextField)
            return
        }

        func doSignUp(pub: TheCard) {
            let desc = MetaSetDesc<TheCard, String>(pub: pub, priv: nil)
            desc.attachments = pub.photoRefs
            let cred = Credential(meth: method!, val: credential)
            var creds = [Credential]()
            creds.append(cred)

            UiUtils.toggleProgressOverlay(in: self, visible: true, title: NSLocalizedString("Registering...", comment: "Progress overlay"))

            do {
                try Cache.tinode.connectDefault(inBackground: false)?
                    .thenApply { _ in
                        return Cache.tinode.createAccountBasic(uname: login, pwd: pwd, login: true, tags: nil, desc: desc, creds: creds)
                    }
                    .thenApply { [weak self] msg in
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

        if let imageBits = avatar?.pixelData(forMimeType: Photo.kDefaultType) {
            if imageBits.count > UiUtils.kMaxInbandAvatarBytes {
                // Sending image out of band.
                Cache.getLargeFileHelper().startAvatarUpload(mimetype: Photo.kDefaultType, data: imageBits, topicId: Tinode.kTopicMe, completionCallback: {(srvmsg, error) in
                    guard let error = error else {
                        let thumbnail = avatar!.resize(width: UiUtils.kAvatarPreviewDimensions, height: UiUtils.kAvatarPreviewDimensions, clip: true)
                        let photo = Photo(data: thumbnail?.pixelData(forMimeType: Photo.kDefaultType), ref: srvmsg?.ctrl?.getStringParam(for: "url"), width: Int(avatar!.size.width), height: Int(avatar!.size.height))
                        doSignUp(pub: TheCard(fn: name, avatar: photo))
                        return
                    }
                    UiUtils.ToastFailureHandler(err: error)
                })
                return
            }
        }
        doSignUp(pub: TheCard(fn: name, avatar: avatar))
    }
}

extension SignupViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?, mimeType: String?, fileName: String?) {
        guard let image = image?.resize(width: CGFloat(UiUtils.kMaxAvatarSize), height: CGFloat(UiUtils.kMaxAvatarSize), clip: true) else { return }

        self.avatarImageView.image = image
        avatarReceived = true
    }
}
