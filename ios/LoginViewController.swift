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

        // TODO: move this logic to the splash screen.
        if let token = KeychainWrapper.standard.string(
            forKey: LoginViewController.kTokenKey), !token.isEmpty {
            let tinode = Cache.getTinode()
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    // TODO: implement TLS.
                    _ = try tinode.connect(to: Cache.kHostName, useTLS: false)?.getResult()
                    let msg = try tinode.loginToken(token: token, creds: nil).getResult()
                    if let code = msg.ctrl?.code, code < 300 {
                        print("login successful for: \(tinode.myUid!)")
                        self.routeToChats()
                    }
                } catch {
                    print("Failed to automatically login to Tinode: \(error).")
                }
            }
        }
    }
    
    private func routeToChats() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let destinationVC = storyboard.instantiateViewController(withIdentifier: "MainNavigator") as! UINavigationController
        
        self.show(destinationVC, sender: nil)
    }
    
    @IBAction func loginClicked(_ sender: Any) {
        if let userName = userNameTextEdit.text, let password = passwordTextEdit.text {
            let tinode = Cache.getTinode()
            // TODO: implement TLS.
            do {
                try tinode.connect(to: Cache.kHostName, useTLS: false)?
                    .then(
                        onSuccess: { pkt in
                            return try tinode.loginBasic(uname: userName, password: password)
                        }, onFailure: nil)?
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
                        }, onFailure: nil)
            } catch {
                //os_log("Failed to connect/login to Tinode: %s.", log: OSLog.default, type: .error, error as CVarArg)
                print("Failed to connect/login to Tinode: \(error).")
            }
        }
    }
    
}
