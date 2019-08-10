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
/*
        let tap = UITapGestureRecognizer(target: self.view, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        self.view.addGestureRecognizer(tap)
 */
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        let userInfo: NSDictionary = notification.userInfo! as NSDictionary
        let keyboardSize = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.size

        let tabbarHeight = tabBarController?.tabBar.frame.size.height ?? 0
        let toolbarHeight = navigationController?.toolbar.frame.size.height ?? 0
        let bottomInset = keyboardSize.height - tabbarHeight - toolbarHeight

        scrollView.contentInset.bottom = bottomInset
        scrollView.scrollIndicatorInsets.bottom = bottomInset
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

        if userName == "" || password == "" {
            print("form elements are empty")
            return
        }

        let tinode = Cache.getTinode()
        let (hostName, useTLS, _) = SettingsHelper.getConnectionSettings()
        print("connecting to \(hostName), useTLS = \(useTLS)")
        UiUtils.toggleProgressOverlay(in: self, visible: true, title: "Logging in...")
        do {
            try tinode.connect(to: (hostName ?? Cache.kHostName), useTLS: (useTLS ?? false))?
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
                        UiUtils.routeToChatListVC()
                        return nil
                    }, onFailure: { err in
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
                            UiUtils.showToast(message: toastMsg)
                        }
                        _ = tinode.logout()
                        return nil
                    })?.thenFinally { [weak self] in
                        guard let loginVC = self else { return }
                        DispatchQueue.main.async {
                            UiUtils.toggleProgressOverlay(in: loginVC, visible: false)
                        }
                    }
            } catch {
                UiUtils.toggleProgressOverlay(in: self, visible: false)
                //os_log("Failed to connect/login to Tinode: %s.", log: OSLog.default, type: .error, error as CVarArg)
                print("Failed to connect/login to Tinode: \(error).")
                _ = tinode.logout()
            }
    }
}
