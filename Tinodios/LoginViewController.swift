//
//  LoginViewController.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import UIKit
import os
import SwiftKeychainWrapper

class LoginViewController: UIViewController {

    @IBOutlet weak var userNameTextEdit: UITextField!
    @IBOutlet weak var passwordTextEdit: UITextField!
    
    static let kTokenKey = "co.tinode.token"
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Listen to text change events
        userNameTextEdit.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        passwordTextEdit.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
    }
    
    private func routeToChats() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let destinationVC = storyboard.instantiateViewController(withIdentifier: "ChatsNavigator") as! UINavigationController
        
        self.show(destinationVC, sender: nil)
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        // Reset red border to default.
        textField.layer.borderWidth = 0.0
    }

    @IBAction func loginClicked(_ sender: Any) {
        let userName = isTextFieldValid(userNameTextEdit)
        let password = isTextFieldValid(passwordTextEdit)

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
                        return try tinode.loginBasic(uname: userName, password: password)
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
                        self?.routeToChats()
                        return nil
                    })
        } catch {
            //os_log("Failed to connect/login to Tinode: %s.", log: OSLog.default, type: .error, error as CVarArg)
            print("Failed to connect/login to Tinode: \(error).")
        }
    }

    private func isTextFieldValid(_ field: UITextField) -> String {
        let text = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if (text.isEmpty) {
            // Make border red to signify error.
            field.layer.borderColor = UIColor.red.cgColor
            field.layer.borderWidth = 1.0
            return ""
        }
        return text
    }
}
