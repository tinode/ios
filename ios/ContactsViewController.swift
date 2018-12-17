//
//  ViewController.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import UIKit

class ContactsViewController: UITableViewController {
    private class MeListener: DefaultMeTopic.Listener {
        private weak var adapter: ChatListAdaper?
        init(adapter: ChatListAdaper?) {
            self.adapter = adapter
        }
        override func onInfo(info: MsgServerInfo) {
            print("Contacts got onInfo update \(String(describing: info.what))")
        }
        
        override func onPres(pres: MsgServerPres) {
            if pres.what == "msg" || pres.what == "off" || pres.what == "on" {
                //datasetChanged()
                print("dataset changed")
                adapter?.update()
            }
        }
        
        
        override func onMetaSub(sub: Subscription<VCard, PrivateType>) {
            // TODO: sub.pub?.constructBitmap()
            print("on meta sub")
        }
        
        override func onMetaDesc(desc: Description<VCard, PrivateType>) {
            // TODO: desc.pub?.constructBitmap()
            print("on meta desc")
        }
        
        override func onSubsUpdated() {
            // datasetChanged()
            print("on subs updated")
        }
        
        override func onContUpdate(sub: Subscription<VCard, PrivateType>) {
            // Method makes no sense in context of MeTopic.
            // throw new UnsupportedOperationException();
        }
    }
    var adapter: ChatListAdaper?
    private var meListener: MeListener?
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        adapter = ChatListAdaper(for: self.tableView)
        meListener = MeListener(adapter: adapter)
        // Attach to ME topic.
        attachToMeTopic(l: meListener)
        adapter!.resetTopics()
        
        // TODO: delete this
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let a = self?.adapter else {
                return
            }
            a.resetTopics()
            self?.tableView.reloadData()
        }
    }
    private func routeToLogin() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let destinationVC = storyboard.instantiateViewController(withIdentifier: "StartNavigator") as! UINavigationController
        self.show(destinationVC, sender: nil)
    }
    private func attachToMeTopic(l: MeListener?) {
        let tinode = Cache.getTinode()
        var me = tinode.getMeTopic()
        if me == nil  {
            me = try! DefaultMeTopic(tinode: tinode, l: l)
        } else {
            me!.listener = l
        }
        let get = me!.getMetaGetBuilder().withGetDesc().withGetSub().build()
        let _ = try? me!.subscribe(set: nil, get: get).then(
            onSuccess: { msg in
                //msg
                print("msg = ")
                return nil
            },
            onFailure: { [weak self] err in
                print("err = ")
                if let e = err as? TinodeError, case .serverResponseError(let code, _, _) = e {
                    if code == 404 {
                        tinode.logout()
                        self?.routeToLogin()
                    }
                }
                return nil
        })
    }

}

extension ContactsViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let c = adapter!.topicCount()
        return c
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "ChatsTableViewCell")
        
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "ChatsTableViewCell")
        }
        
        let topic = adapter!.topics![indexPath.row]
        
        /*
        if contact.isOnline == false {
            cell?.detailTextLabel?.textColor = UIColor.lightGray
        }
        */
        cell?.textLabel?.text = topic.pub?.fn ?? "Unknown or unnamed"
        cell?.detailTextLabel?.text = "todo"//topic.online
        
        return cell!
    }
}
