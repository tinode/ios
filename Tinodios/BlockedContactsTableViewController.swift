//
//  BlockedContactsTableViewController.swift
//  Tinodios
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class BlockedContactsTableViewController: UITableViewController {

    @IBOutlet var chatListTableView: UITableView!

    private var topics: [DefaultComTopic] = []
    override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.tableFooterView = UIView(frame: .zero)
        self.chatListTableView.register(UINib(nibName: "ChatListViewCell", bundle: nil), forCellReuseIdentifier: "ChatListViewCell")
        self.reloadData()
    }

    private func reloadData() {
        self.topics = Cache.tinode.getFilteredTopics(filter: {(topic: TopicProto) in
            return topic.topicType.matches(TopicType.user) && !topic.isJoiner
        })?.map {
            // Must succeed.
            $0 as! DefaultComTopic
        } ?? []
    }
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.topics.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatListViewCell") as! ChatListViewCell

        let topic = self.topics[indexPath.row]
        cell.fillFromTopic(topic: topic)
        return cell
    }

    private func handleSuccess(_ vc: BlockedContactsTableViewController) {
        DispatchQueue.main.async {
            vc.reloadData()
            vc.tableView.reloadData()
            // If there are no more blocked topics, close the view.
            if vc.topics.isEmpty {
                vc.navigationController?.popViewController(animated: true)
                vc.dismiss(animated: true, completion: nil)
            }
        }
    }

    private func unblockTopic(topic: DefaultComTopic) {
        topic.subscribe().then(
            onSuccess: { [weak self] _ in
                if let vc = self {
                    vc.handleSuccess(vc)
                }
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler
        )
        topic.leave()
    }

    private func deleteTopic(_ name: String) {
        let topic = Cache.tinode.getTopic(topicName: name) as! DefaultComTopic
        topic.delete(hard: true).then(
            onSuccess: { [weak self] _ in
                if let vc = self {
                    vc.handleSuccess(vc)
                }
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler
        )
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Delete item at indexPath
        let delete = UIContextualAction(style: .destructive, title: NSLocalizedString("Delete", comment: "Swipe action"), handler: { _,_,_ in
                let topic = self.topics[indexPath.row]
                self.deleteTopic(topic.name)
        })
        // Unblock item.
        let unblock = UIContextualAction(style: .normal, title: NSLocalizedString("Unblock", comment: "Swipe action"), handler: { _,_,_ in
                let topic = self.topics[indexPath.row]
                self.unblockTopic(topic: topic)
        })

        return UISwipeActionsConfiguration(actions: [delete, unblock])
    }
}
