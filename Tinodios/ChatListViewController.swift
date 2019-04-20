//
//  ViewController.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import UIKit
import MessageKit
import TinodeSDK

protocol ChatListDisplayLogic: class {
    func displayChats(_ topics: [DefaultComTopic])
    func displayLoginView()
    func updateChat(_ name: String)
}

class ChatListViewController: UITableViewController, ChatListDisplayLogic {

    var interactor: ChatListBusinessLogic?
    var topics: [DefaultComTopic] = []
    // Index of contacts: name => position in topics
    var rowIndex: Dictionary<String, Int> = Dictionary()
    var router: ChatListRoutingLogic?

    private func setup() {
        let viewController = self
        let interactor = ChatListInteractor()
        let presenter = ChatListPresenter()
        let router = ChatListRouter()

        viewController.interactor = interactor
        viewController.router = router
        interactor.presenter = presenter
        interactor.router = router
        presenter.viewController = viewController
        router.viewController = viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        setup()
        self.interactor?.attachToMeTopic()
    }

    override func viewDidAppear(_ animated: Bool) {
        self.interactor?.loadAndPresentTopics()
    }
    override func viewDidDisappear(_ animated: Bool) {
        self.interactor?.cleanup()
    }

    func displayLoginView() {
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let destinationVC = storyboard.instantiateViewController(withIdentifier: "StartNavigator") as! UINavigationController
            self.show(destinationVC, sender: nil)
        }
    }

    func displayChats(_ topics: [DefaultComTopic]) {
        self.topics = topics
        self.rowIndex = Dictionary(uniqueKeysWithValues: topics.enumerated().map { (index, topic) in (topic.name, index) })
        DispatchQueue.main.async {
            self.tableView!.reloadData()
        }
    }

    func updateChat(_ name: String) {
        guard let position = rowIndex[name] else { return }
        
        print("Update chat \(name) in position \(position)")

        DispatchQueue.main.async {
            self.tableView!.reloadRows(at: [IndexPath(item: position, section: 0)], with: .none)
        }
    }
}

extension ChatListViewController {
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Chats2Messages" {
            router?.routeToChat(segue: segue)
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return topics.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatsTableViewCell") as! ChatListTableViewCell
        let topic = self.topics[indexPath.row]
        cell.title.text = topic.pub?.fn ?? "Unknown or unnamed"
        cell.title.sizeToFit()
        cell.subtitle.text = topic.comment
        cell.subtitle.sizeToFit()
        let unread = topic.unread
        if unread > 0 {
            cell.unreadCount.text = unread > 9 ? "9+" : String(unread)
            cell.unreadCount.isHidden = false
        } else {
            cell.unreadCount.isHidden = true
        }

        // Online/offline indicator
        cell.online.backgroundColor = topic.online ?
            UIColor.init(red: 0x40/255, green: 0xC0/255, blue: 0x40/255, alpha: 1.0) :
            UIColor.init(red: 0xE0/255, green: 0xE0/255, blue: 0xE0/255, alpha: 1.0)

        // Avatar image
        cell.icon.set(icon: topic.pub?.photo?.image(), title: topic.pub?.fn, id: topic.name)

        return cell
    }
}
