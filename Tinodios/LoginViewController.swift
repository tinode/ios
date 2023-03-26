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
import TinodiosDB

class LoginViewController: UIViewController {

    @IBOutlet weak var userNameTextEdit: UITextField!
    @IBOutlet weak var passwordTextEdit: UITextField!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var logoView: UIImageView!
    @IBOutlet weak var serviceNameLabel: UILabel!
    @IBOutlet weak var poweredByStack: UIStackView!
    @IBOutlet weak var configureConnectionButton: UIButton!

    override func loadView() {
        super.loadView()
        // This is needed in order to adjust the height of the scroll view when the keyboard appears.
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIControl.keyboardWillShowNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIControl.keyboardWillHideNotification, object: self)
        // Make sure LoginVC gets notified when app logo icon becomes available.
        NotificationCenter.default.addObserver(self, selector: #selector(logoAvailable(_:)), name: Notification.Name(SharedUtils.kNotificationBrandingSmallIconAvailable), object: nil)
        // Get notified with the branding service name becomes available.
        NotificationCenter.default.addObserver(self, selector: #selector(brandingConfigAvailable(_:)), name: Notification.Name(SharedUtils.kNotificationBrandingConfigAvailable), object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Listen to text change events
        userNameTextEdit.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        passwordTextEdit.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        passwordTextEdit.showSecureEntrySwitch()

        UiUtils.dismissKeyboardForTaps(onView: self.view)

        if SharedUtils.appId != nil {
            // Branding is configured. Show "Powered by" view, hide configureConnectionButton.
            self.poweredByStack.isHidden = false
            self.configureConnectionButton.isHidden = true
        } else {
            // Branding is not configured. Show "Configure connection" button, hide "Powered by" view.
            self.configureConnectionButton.isHidden = false
            self.poweredByStack.isHidden = true
        }
        if let logo = SharedUtils.smallIcon {
            self.logoView.image = logo
        }
        if let serviceName = SharedUtils.serviceName {
            self.serviceNameLabel.text = serviceName
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidShowNotification, object: self)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: self)
        NotificationCenter.default.removeObserver(self, name: Notification.Name(SharedUtils.kNotificationBrandingSmallIconAvailable), object: self)
        NotificationCenter.default.removeObserver(self, name: Notification.Name(SharedUtils.kNotificationBrandingConfigAvailable), object: self)
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
        if traitCollection.userInterfaceStyle == .dark {
            self.view.backgroundColor = .black
        } else {
            self.view.backgroundColor = .white
        }
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        let userInfo: NSDictionary = notification.userInfo! as NSDictionary
        let keyboardScreenEndFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue

        let keyboardViewEndFrame = view.convert(keyboardScreenEndFrame, from: view.window)

        let bottomInset = keyboardViewEndFrame.height - view.safeAreaInsets.bottom

        scrollView.contentInset.bottom = bottomInset
        scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
    }

    // Logo image has just been downloaded. Use it.
    @objc func logoAvailable(_ notification: Notification) {
        guard let logo = notification.object as? UIImage else {
            Cache.log.error("LoginVC: logo available notification with an empty payload")
            return
        }
        DispatchQueue.main.async { self.logoView.image = logo }
    }

    // Service name has just become available. Use it.
    @objc func brandingConfigAvailable(_ notification: Notification) {
        DispatchQueue.main.async {
            if SharedUtils.appId != nil {
                self.configureConnectionButton.isHidden = true
                self.poweredByStack.isHidden = false
            }
            if let serviceName = SharedUtils.serviceName {
                self.serviceNameLabel.text = serviceName
            }
        }
    }

    @IBAction func loginClicked(_ sender: Any) {
        let userName = UiUtils.ensureDataInTextField(userNameTextEdit)
        let password = UiUtils.ensureDataInTextField(passwordTextEdit)

        guard !userName.isEmpty && !password.isEmpty else { return }

        let tinode = Cache.tinode
        UiUtils.toggleProgressOverlay(in: self, visible: true, title: NSLocalizedString("Logging in...", comment: "Login progress text"))
        do {
            try tinode.connectDefault(inBackground: false)?
                .thenApply({ _ in
                        return tinode.loginBasic(uname: userName, password: password)
                    })
                .then(
                    onSuccess: { [weak self] pkt in
                        Cache.log.info("LoginVC - login successful for %@", tinode.myUid!)
                        SharedUtils.saveAuthToken(for: userName, token: tinode.authToken, expires: tinode.authTokenExpires)
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
                        } else {
                            let (hostName, _) = Tinode.getConnectionParams()
                            toastMsg = String(format: NSLocalizedString("Couldn't connect to server at %@: %@", comment: "Error message"), hostName, err.localizedDescription)
                        }
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: toastMsg)
                        }
                        Cache.invalidate()
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
                tinode.logout()
            }
    }
}
