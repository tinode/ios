//
//  LoginViewController.swift
//  Tinodios
//
//  Copyright © 2018 Tinode. All rights reserved.
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

    static let kTokenKey = "co.tinode.token"

    override func viewDidLoad() {
        super.viewDidLoad()

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
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.navigationBar.isHidden = false
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        let userInfo: NSDictionary = notification.userInfo! as NSDictionary
        let keyboardSize = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.size

        let tabbarHeight = tabBarController?.tabBar.frame.size.height ?? 0
        let toolbarHeight = navigationController?.toolbar.frame.size.height ?? 0
        let bottomInset = keyboardSize.height - tabbarHeight - toolbarHeight

        scrollView.contentInset.bottom = bottomInset
        scrollView.scrollIndicatorInsets.bottom = bottomInset

        // If active text field is hidden by the keyboard, scroll it into view.
        var visibleRect = self.view.frame
        visibleRect.size.height -= keyboardSize.height
        if let activeField = [userNameTextEdit, passwordTextEdit].first(where: { $0.isFirstResponder }) {
            print("visible \(visibleRect); active origin \(activeField.frame.origin)")
            if visibleRect.contains(activeField.frame.origin) {
                let scrollPoint = CGPoint(x: 0, y: activeField.frame.origin.y - keyboardSize.height)
                scrollView.setContentOffset(scrollPoint, animated: true)
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

    @IBAction func loginClicked(_ sender: Any) {
        let userName = UiUtils.ensureDataInTextField(userNameTextEdit)
        let password = UiUtils.ensureDataInTextField(passwordTextEdit)

        guard !userName.isEmpty && !password.isEmpty else { return }

        let tinode = Cache.getTinode()
        UiUtils.toggleProgressOverlay(in: self, visible: true, title: "Logging in...")
        do {
            try tinode.connectDefault()?
                .then(
                    onSuccess: { pkt in
                        return tinode.loginBasic(uname: userName, password: password)
                    })?
                .then(
                    onSuccess: { [weak self] pkt in
                        print("login successful for: \(tinode.myUid!)")
                        Utils.saveAuthToken(for: userName, token: tinode.authToken)
                        if let ctrl = pkt?.ctrl, ctrl.code >= 300, ctrl.text.contains("validate credentials") {
                            UiUtils.routeToCredentialsVC(in: self?.navigationController,
                                                         verifying: ctrl.getStringArray(for: "cred")?.first)
                            return nil
                        }
                        Cache.synchronizeContactsPeriodically()
                        if let loginVC = self {
                            UiUtils.toggleProgressOverlay(in: loginVC, visible: false)
                            UiUtils.routeToChatListVC()
                        }
                        return nil
                    }, onFailure: { [weak self] err in
                        print("failed to login \(err)")
                        var toastMsg: String
                        if let tinodeErr = err as? TinodeError {
                            toastMsg = "Tinode: \(tinodeErr.description)"
                        } else if let nwErr = err as? SwiftWebSocket.WebSocketError {
                            toastMsg = "Couldn't connect to server: \(nwErr)"
                        } else {
                            toastMsg = err.localizedDescription
                        }
                        DispatchQueue.main.async {
                            if let loginVC = self {
                                UiUtils.toggleProgressOverlay(in: loginVC, visible: false)
                            }
                            UiUtils.showToast(message: toastMsg)
                        }
                        _ = tinode.logout()
                        return nil
                    })
            } catch {
                UiUtils.toggleProgressOverlay(in: self, visible: false)
                //os_log("Failed to connect/login to Tinode: %s.", log: OSLog.default, type: .error, error as CVarArg)
                print("Failed to connect/login to Tinode: \(error).")
                _ = tinode.logout()
            }
    }
}
