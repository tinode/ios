//
//  LoginViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import os
import SwiftKeychainWrapper
import TinodeSDK
import SwiftWebSocket

class LoginViewController: UIViewController {

    @IBOutlet weak var userNameTextEdit: UITextField!
    @IBOutlet weak var passwordTextEdit: UITextField!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet var passwordVisibility: [UIButton]!
    private var passwordVisible: Bool = false

    static let kTokenKey = "co.tinode.token"

    override func viewDidLoad() {
        super.viewDidLoad()

        UiUtils.adjustPasswordVisibilitySwitchColor(for: passwordVisibility, setColor: .darkGray)

        // Listen to text change events
        userNameTextEdit.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        passwordTextEdit.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)

        // This is needed in order to adjust the height of the scroll view when the keyboard appears.
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIControl.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIControl.keyboardWillHideNotification, object: nil)

        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.navigationBar.isHidden = true
        self.setInterfaceColors()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.navigationBar.isHidden = false
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        self.setInterfaceColors()
    }

    private func setInterfaceColors() {
        if #available(iOS 12.0, *), traitCollection.userInterfaceStyle == .dark {
            self.view.backgroundColor = .black
        } else {
            self.view.backgroundColor = .white
        }
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        let userInfo: NSDictionary = notification.userInfo! as NSDictionary
        let keyboardScreenEndFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue

        let keyboardViewEndFrame = view.convert(keyboardScreenEndFrame, from: view.window)

        let bottomInset: CGFloat
        if #available(iOS 11.0, *) {
            bottomInset = keyboardViewEndFrame.height - view.safeAreaInsets.bottom
        } else {
            let tabbarHeight = tabBarController?.tabBar.frame.size.height ?? 0
            let toolbarHeight = navigationController?.toolbar.frame.size.height ?? 0
            bottomInset = keyboardViewEndFrame.height - tabbarHeight - toolbarHeight
        }

        scrollView.contentInset.bottom = bottomInset
        scrollView.scrollIndicatorInsets.bottom = bottomInset

        if #available(iOS 11.0, *) {} else {
            // If active text field is hidden by the keyboard, scroll it into view.
            var visibleRect = view.frame
            visibleRect.size.height -= bottomInset
            if let activeField = [userNameTextEdit, passwordTextEdit].first(where: { $0.isFirstResponder }),
                // passwordTextField is embedded in a text view (in order to display password visibility switches).
                let origin = (activeField === passwordTextEdit! ? activeField.superview : activeField)?.frame.origin {
                if visibleRect.contains(origin) {
                    let scrollPoint = CGPoint(x: 0, y: origin.y - bottomInset)
                    scrollView.setContentOffset(scrollPoint, animated: true)
                }
            }
        }
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        UiUtils.clearTextFieldError(textField)
    }

    @IBAction func passwordVisibilityClicked(_ sender: Any) {
        passwordTextEdit.isSecureTextEntry = passwordVisible
        passwordVisible = !passwordVisible
        for v in passwordVisibility {
            v.isHidden = !v.isHidden
        }
    }

    @IBAction func loginClicked(_ sender: Any) {
        let userName = UiUtils.ensureDataInTextField(userNameTextEdit)
        let password = UiUtils.ensureDataInTextField(passwordTextEdit)

        guard !userName.isEmpty && !password.isEmpty else { return }

        let tinode = Cache.getTinode()
        UiUtils.toggleProgressOverlay(in: self, visible: true, title: "Logging in...")
        do {
            try tinode.connectDefault()?
                .thenApply({ pkt in
                        return tinode.loginBasic(uname: userName, password: password)
                    })
                .then(
                    onSuccess: { [weak self] pkt in
                        Cache.log.info("LoginVC - login successful for %@", tinode.myUid!)
                        Utils.saveAuthToken(for: userName, token: tinode.authToken)
                        if let token = tinode.authToken {
                            tinode.setAutoLoginWithToken(token: token)
                        }
                        if let ctrl = pkt?.ctrl, ctrl.code >= 300, ctrl.text.contains("validate credentials") {
                            DispatchQueue.main.async {
                                UiUtils.routeToCredentialsVC(in: self?.navigationController,
                                                             verifying: ctrl.getStringArray(for: "cred")?.first)
                            }
                            return nil
                        }
                        UiUtils.routeToChatListVC()
                        return nil
                    }, onFailure: { err in
                        Cache.log.error("LoginVC - login failed: %@", err.localizedDescription)
                        var toastMsg: String
                        if let tinodeErr = err as? TinodeError {
                            toastMsg = "Tinode: \(tinodeErr.description)"
                        } else if let nwErr = err as? SwiftWebSocket.WebSocketError {
                            toastMsg = "Couldn't connect to server: \(nwErr)"
                        } else {
                            toastMsg = err.localizedDescription
                        }
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: toastMsg)
                        }
                        _ = tinode.logout()
                        return nil
                    }).thenFinally { [weak self] in
                        guard let loginVC = self else { return }
                        DispatchQueue.main.async {
                            UiUtils.toggleProgressOverlay(in: loginVC, visible: false)
                        }
                    }
            } catch {
                UiUtils.toggleProgressOverlay(in: self, visible: false)
                Cache.log.error("LoginVC - Failed to connect/login to Tinode: %@", error.localizedDescription)
                _ = tinode.logout()
            }
    }
}
