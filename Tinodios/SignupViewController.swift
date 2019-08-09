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

    var imagePicker: ImagePicker!
    var uploadedAvatar: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        self.imagePicker = ImagePicker(presentationController: self, delegate: self)

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

    @IBAction func signUpClicked(_ sender: Any) {
        let login = UiUtils.ensureDataInTextField(loginTextField)
        let pwd = UiUtils.ensureDataInTextField(passwordTextField)
        let name = UiUtils.ensureDataInTextField(nameTextField)
        let credential = UiUtils.ensureDataInTextField(emailPhoneTextField)

        guard !login.isEmpty && !pwd.isEmpty && !name.isEmpty && !credential.isEmpty else { return }

        var method: String? = nil
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

        signUpButton.isUserInteractionEnabled = false
        let tinode = Cache.getTinode()

        let avatar = uploadedAvatar ? avatarImageView?.image?.resize(width: UiUtils.kAvatarSize, height: UiUtils.kAvatarSize, clip: true) : nil
        let vcard = VCard(fn: name, avatar: avatar)

        let desc = MetaSetDesc<VCard, String>(pub: vcard, priv: nil)
        let cred = Credential(meth: method!, val: credential)
        var creds = [Credential]()
        creds.append(cred)
        UiUtils.toggleProgressOverlay(in: self, visible: true, title: "Registering...")
        do {
            let future = !tinode.isConnected ?
                try tinode.connect(to: Cache.kHostName, useTLS: false)?.thenApply(
                    onSuccess: { pkt in
                        return tinode.createAccountBasic(
                            uname: login, pwd: pwd, login: true,
                            tags: nil, desc: desc, creds: creds)
                }) :
                tinode.createAccountBasic(
                    uname: login, pwd: pwd, login: true,
                    tags: nil, desc: desc, creds: creds)

            try future?.then(
                onSuccess: { [weak self] msg in
                    if let ctrl = msg?.ctrl, ctrl.code >= 300, ctrl.text.contains("validate credentials") {
                        UiUtils.routeToCredentialsVC(in: self?.navigationController,
                                                     verifying: ctrl.getStringArray(for: "cred")?.first)
                    } else {
                        let storyboard = UIStoryboard(name: "Main", bundle: nil)
                        let destinationVC = storyboard.instantiateViewController(withIdentifier: "ChatsNavigator") as! UINavigationController
                        DispatchQueue.main.async {
                            self?.show(destinationVC, sender: nil)
                        }
                    }
                    return nil
                }, onFailure: { err in
                    DispatchQueue.main.async {
                        UiUtils.showToast(message: "Failed to create account: \(err.localizedDescription)")
                    }
                    tinode.disconnect()
                    print("Could not create account: \(err)")
                    return nil
            })?.thenFinally(finally: { [weak self] in
                guard let signupVC = self else { return }
                DispatchQueue.main.async {
                    signupVC.signUpButton.isUserInteractionEnabled = true
                    UiUtils.toggleProgressOverlay(in: signupVC, visible: false)
                }
            })
        } catch {
            print("Failed to connect/createAccountBasic to Tinode: \(error).")
            tinode.disconnect()
            DispatchQueue.main.async {
                UiUtils.showToast(message: "Failed to create account: \(error.localizedDescription)")
                self.signUpButton.isUserInteractionEnabled = true
                UiUtils.toggleProgressOverlay(in: self, visible: false)
            }
        }
    }
}

extension SignupViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?, mimeType: String?, fileName: String?) {
        guard let image = image?.resize(width: CGFloat(UiUtils.kAvatarSize), height: CGFloat(UiUtils.kAvatarSize), clip: true) else {
            print("No image specified or failed to resize - skipping")
            return
        }

        self.avatarImageView.image = image
        uploadedAvatar = true
    }
}

