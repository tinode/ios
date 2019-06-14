//
//  ChatListViewController.swift
//  Tinodios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

protocol ChatListDisplayLogic: class {
    func displayChats(_ topics: [DefaultComTopic])
    func displayLoginView()
    func updateChat(_ name: String)
    func deleteChat(_ name: String)
}

class ChatListViewController: UITableViewController, ChatListDisplayLogic {

    var interactor: ChatListBusinessLogic?
    var topics: [DefaultComTopic] = []
    // Index of contacts: name => position in topics
    var rowIndex: [String : Int] = [:]
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

        NotificationCenter.default.addObserver(
            self, selector: #selector(self.appGoingInactive),
            name: UIApplication.willResignActiveNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.appBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }
    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willResignActiveNotification,
            object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }
    @objc
    func appBecameActive() {
        self.interactor?.attachToMeTopic()
    }
    @objc
    func appGoingInactive() {
        self.interactor?.cleanup()
        self.interactor?.leaveMeTopic()
    }

    override func viewDidAppear(_ animated: Bool) {
        self.interactor?.setup()
        self.interactor?.attachToMeTopic()
        self.interactor?.loadAndPresentTopics()
    }
    override func viewDidDisappear(_ animated: Bool) {
        self.interactor?.cleanup()
    }

    func displayLoginView() {
        UiUtils.routeToLoginVC()
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
        DispatchQueue.main.async {
            self.tableView!.reloadRows(at: [IndexPath(item: position, section: 0)], with: .none)
        }
    }

    func deleteChat(_ name: String) {
        guard let position = rowIndex[name] else { return }
        DispatchQueue.main.async {
            self.topics.remove(at: position)
            self.tableView!.deleteRows(at: [IndexPath(item: position, section: 0)], with: .fade)
        }
    }
}

// UITableViewController
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
        toggleNoChatsNote(on: topics.isEmpty)
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

    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        // Delete item at indexPath
        let delete = UITableViewRowAction(style: .destructive, title: "Delete") { (action, indexPath) in
            let topic = self.topics[indexPath.row]
            self.interactor?.deleteTopic(topic.name)
        }

        return [delete]
    }
}

extension ChatListViewController {

    /// Show notification that the chat list is empty
    public func toggleNoChatsNote(on show: Bool) {
        if show {
            let rect = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height)
            let messageLabel = UILabel(frame: rect)
            messageLabel.text = "You have no chats\n\n¯\\_(ツ)_/¯"
            messageLabel.textColor = .darkGray
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            messageLabel.font = UIFont.preferredFont(forTextStyle: .body)
            messageLabel.sizeToFit()

            tableView.backgroundView = messageLabel
        } else {
            tableView.backgroundView = nil
        }
    }
}
