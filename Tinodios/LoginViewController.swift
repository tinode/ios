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

    private func routeToChats() {
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let destinationVC = storyboard.instantiateViewController(withIdentifier: "ChatsNavigator") as! UINavigationController

            if let window = UIApplication.shared.keyWindow {
                // Use ChatList as the new root view controller (used in navigation).
                window.rootViewController = destinationVC
             }
        }
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
                        UserDefaults.standard.set(userName, forKey: Utils.kTinodePrefLastLogin)
                        if let token = tinode.authToken, !token.isEmpty {
                            let tokenSaveSuccessful = KeychainWrapper.standard.set(
                                token, forKey: LoginViewController.kTokenKey)
                            if !tokenSaveSuccessful {
                                print("Could not save auth token...")
                            }
                        }
                        // TODO: handle credentials validation (pkt.ctrl.code >= 300).
                        Cache.synchronizeContactsPeriodically()
                        if let loginVC = self {
                            UiUtils.toggleProgressOverlay(in: loginVC, visible: false)
                            loginVC.routeToChats()
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
