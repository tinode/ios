//
//  LoginViewController.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import UIKit
import os
import SwiftKeychainWrapper
import TinodeSDK

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

            self.show(destinationVC, sender: nil)
        }
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        UiUtils.clearTextFieldError(textField)
    }

    @IBAction func loginClicked(_ sender: Any) {
        let userName = UiUtils.ensureDataInTextField(userNameTextEdit)
        let password = UiUtils.ensureDataInTextField(passwordTextEdit)

        if (userName == "" || password == "") {
            print("form elements are empty")
            return
        }

        let tinode = Cache.getTinode()
        // TODO: implement TLS.
        do {
            try tinode.connect(to: Cache.kHostName, useTLS: false)?
                .then(
                    onSuccess: { pkt in
                        return tinode.loginBasic(uname: userName, password: password)
                    })?
                .then(
                    onSuccess: { [weak self] pkt in
                        print("login successful for: \(tinode.myUid!)")
                        if let token = tinode.authToken, !token.isEmpty {
                            let tokenSaveSuccessful = KeychainWrapper.standard.set(
                                token, forKey: LoginViewController.kTokenKey)
                            if !tokenSaveSuccessful {
                                print("Could not save auth token...")
                            }
                        }
                        // TODO: handle credentials validation (pkt.ctrl.code >= 300).
                        Cache.synchronizeContactsPeriodically()
                        self?.routeToChats()
                        return nil
                    }, onFailure: { err in
                        print("failed to login \(err)")
                        if let err = err as? TinodeError {
                            DispatchQueue.main.async {
                                self.showToast(message: "Login failed: \(err.description)")
                            }
                        }
                        _ = tinode.logout()
                        return nil
                    })
            } catch {
                //os_log("Failed to connect/login to Tinode: %s.", log: OSLog.default, type: .error, error as CVarArg)
                print("Failed to connect/login to Tinode: \(error).")
                _ = tinode.logout()
            }
    }
}
