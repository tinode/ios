//
//  RegisterViewController.swift
//  Tinodios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import UIKit
import TinodeSDK

class RegisterViewController: UIViewController {
    @IBOutlet weak var loginText: UITextField!
    @IBOutlet weak var pwdText: UITextField!
    @IBOutlet weak var nameText: UITextField!
    @IBOutlet weak var credentialText: UITextField!
    @IBOutlet weak var signUpBtn: UIButton!
    @IBOutlet weak var loadAvatar: UIButton!
    @IBOutlet weak var avatarView: RoundImageView!

    var imagePicker: ImagePicker!
    var uploadedAvatar: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        self.imagePicker = ImagePicker(presentationController: self, delegate: self)

        // Listen to text change events to clear the possible error from earlier attempt.
        loginText.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        pwdText.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        nameText.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        credentialText.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        UiUtils.clearTextFieldError(textField)
    }
    
    @IBAction func onLoadAvatar(_ sender: UIButton) {
        // Get avatar image
        self.imagePicker.present(from: self.view)
    }

    @IBAction func onSignUp(_ sender: Any) {
        let login = UiUtils.ensureDataInTextField(loginText)
        let pwd = UiUtils.ensureDataInTextField(pwdText)
        let name = UiUtils.ensureDataInTextField(nameText)
        let credential = UiUtils.ensureDataInTextField(credentialText)

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
            UiUtils.markTextFieldAsError(credentialText)
            return
        }
        
        signUpBtn.isUserInteractionEnabled = false
        let tinode = Cache.getTinode()

        let avatar = uploadedAvatar ? avatarView?.image?.resize(width: 128, height: 128, clip: true) : nil
        let vcard = VCard(fn: name, avatar: avatar)

        let desc = MetaSetDesc<VCard, String>(pub: vcard, priv: nil)
        let cred = Credential(meth: method!, val: credential)
        var creds = [Credential]()
        creds.append(cred)
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
                    if let ctrl = msg?.ctrl, ctrl.code >= 300 {
                        let vc = self?.storyboard?.instantiateViewController(withIdentifier: String(describing: type(of: CredentialsViewController()))) as! CredentialsViewController
                        if let cArr = ctrl.getStringArray(for: "cred") {
                            for c in cArr {
                                vc.meth = c
                            }
                        }
                        DispatchQueue.main.async {
                            self?.navigationController?.pushViewController(vc, animated: true)
                        }
                    } else {
                        let storyboard = UIStoryboard(name: "Main", bundle: nil)
                        let destinationVC = storyboard.instantiateViewController(withIdentifier: "ChatsNavigator") as! UINavigationController
                        DispatchQueue.main.async {
                            self?.show(destinationVC, sender: nil)
                        }
                    }
                    return nil
                }, onFailure: { err in
                    print("Could not create account: \(err)")
                    tinode.disconnect()
                    return nil
                })?.thenFinally(finally: { [weak self] in
                    DispatchQueue.main.async {
                        self?.signUpBtn.isUserInteractionEnabled = true
                    }
                    return nil
                })
            
        } catch {
            print("Failed to connect/createAccountBasic to Tinode: \(error).")
            tinode.disconnect()
            DispatchQueue.main.async {
                self.signUpBtn.isUserInteractionEnabled = true
            }
        }
    }
}

extension RegisterViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?, mimeType: String?, fileName: String?) {
        guard let image = image?.resize(width: CGFloat(UiUtils.kAvatarSize), height: CGFloat(UiUtils.kAvatarSize), clip: true) else {
            print("No image specified or failed to resize - skipping")
            return
        }

        self.avatarView.image = image
        uploadedAvatar = true
    }
}
