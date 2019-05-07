//
//  CredentialsViewController.swift
//  Tinodios
//
//  Created by ztimc on 2018/12/26.
//  Copyright © 2018 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class CredentialsViewController : UIViewController {
    
    @IBOutlet weak var codeText: UITextField!
    
    var meth: String?
    
    @IBAction func onConfirm(_ sender: UIButton) {
        guard let code = codeText.text else {
            return
        }
        guard let method = meth else {
            return
        }
        
        let tinode = Cache.getTinode()
        
        guard let token = tinode.authToken else {
            return
        }
        
        let c = Credential(meth: method, val: nil, resp: code, params: nil)
        var creds = [Credential]()
        creds.append(c)
        
        do {
            try tinode.loginToken(token: token, creds: creds)?
                .then(onSuccess: {[weak self] msg in
                    if let code = msg.ctrl?.code, code >= 300 {
                        print("login error")
                    } else {
                        let storyboard = UIStoryboard(name: "Main", bundle: nil)
                        let destinationVC = storyboard.instantiateViewController(withIdentifier: "ChatsNavigator") as! UINavigationController
                        self?.show(destinationVC, sender: nil)
                    }
                    return nil
                    }, onFailure: nil)
        } catch {
            print("Failed to loginToken to Tinode: \(error).")
        }
    }
   
    
    @IBAction func onCancel(_ sender: UIButton) {
        
    }
}
