//
//  ChatListViewController.swift
//  Tinodios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

protocol ChatListDisplayLogic: class {
    func displayChats(_ topics: [DefaultComTopic], archivedTopics: [DefaultComTopic]?)
    func displayLoginView()
    func updateChat(_ name: String)
    func deleteChat(_ name: String)
}

class ChatListViewController: UITableViewController, ChatListDisplayLogic {

    var interactor: ChatListBusinessLogic?
    var topics: [DefaultComTopic] = []
    var archivedTopics: [DefaultComTopic]? = nil
    var numArchivedTopics: Int {
        get { return archivedTopics?.count ?? 0 }
    }
    var topicsSection: Int {
        get { return numArchivedTopics > 0 ? 1 : 0 }
    }
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

    func displayChats(_ topics: [DefaultComTopic], archivedTopics: [DefaultComTopic]?) {
        self.topics = topics
        self.archivedTopics = archivedTopics
        self.rowIndex = Dictionary(uniqueKeysWithValues: topics.enumerated().map { (index, topic) in (topic.name, index) })
        DispatchQueue.main.async {
            self.tableView!.reloadData()
        }
    }

    func updateChat(_ name: String) {
        guard let position = rowIndex[name] else { return }
        DispatchQueue.main.async {
            self.tableView!.reloadRows(at: [IndexPath(item: position, section: self.topicsSection)], with: .none)
        }
    }

    func deleteChat(_ name: String) {
        guard let position = rowIndex[name] else { return }
        DispatchQueue.main.async {
            self.topics.remove(at: position)
            self.tableView!.deleteRows(at: [IndexPath(item: position, section: self.topicsSection)], with: .fade)
        }
    }
}

// UITableViewController
extension ChatListViewController {
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Chats2Messages", let topicName = sender as? String {
            router?.routeToChat(withName: topicName, for: segue)
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1 + (self.numArchivedTopics > 0 ? 1 : 0)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        toggleNoChatsNote(on: topics.isEmpty)
        if self.numArchivedTopics > 0 && section == 0 {
            return 1
        }
        return topics.count
    }
    private func fillInArchivedChatsCell(cell: ChatListTableViewCell) {
        cell.title.text = "Archived Chats"
        cell.title.sizeToFit()
        cell.subtitle.text = self.archivedTopics!.map { $0.pub?.fn ?? "Unknown" }.joined(separator: ", ")
        cell.subtitle.sizeToFit()
        cell.unreadCount.text = self.numArchivedTopics > 9 ? "9+" : String(self.numArchivedTopics)
        cell.icon.avatar.image = nil
        cell.icon.online.isHidden = true
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatsTableViewCell") as! ChatListTableViewCell
        if self.numArchivedTopics > 0 && indexPath.section == 0 {
            fillInArchivedChatsCell(cell: cell)
            return cell
        }
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

        // Avatar image
        cell.icon.set(icon: topic.pub?.photo?.image(), title: topic.pub?.fn, id: topic.name, online: topic.online)

        return cell
    }

    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        // Delete item at indexPath
        let delete = UITableViewRowAction(style: .destructive, title: "Delete") { (action, indexPath) in
            let topic = self.topics[indexPath.row]
            self.interactor?.deleteTopic(topic.name)
        }
        let archive = UITableViewRowAction(style: .normal, title: "Archive") { (action, indexPath) in
            print("archiving at index path")
            let topic = self.topics[indexPath.row]
            self.interactor?.changeArchivedStatus(
                forTopic: topic.name, archived: !topic.isArchived)
        }

        return [delete, archive]
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated:  true)
        let section = indexPath.section
        if self.numArchivedTopics > 0 && section == 0 {
            self.performSegue(withIdentifier: "Chats2Archive", sender: nil)
        } else {
            self.performSegue(withIdentifier: "Chats2Messages",
                              sender: self.topics[indexPath.row].name)
        }
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
