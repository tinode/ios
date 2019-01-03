//
//  LoginViewController.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import UIKit
import os

class LoginViewController: UIViewController {

    @IBOutlet weak var userNameTextEdit: UITextField!
    @IBOutlet weak var passwordTextEdit: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    private func routeToChats() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let destinationVC = storyboard.instantiateViewController(withIdentifier: "MainTabBar") as! UITabBarController
        self.present(destinationVC, animated: true, completion: nil)
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
