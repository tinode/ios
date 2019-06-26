//
//  ArchivedChatsTableViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class ArchivedChatsTableViewController: UITableViewController {

    private var topics: [DefaultComTopic] = []
    override func viewDidLoad() {
        super.viewDidLoad()
        self.reloadData()
    }

    private func reloadData() {
        self.topics = Cache.getTinode().getFilteredTopics(filter: {(topic: TopicProto) in
            return topic.topicType.matches(TopicType.user) && topic.isArchived
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "ArchivedChatsTableViewCell")!

        let topic = self.topics[indexPath.row]
        cell.textLabel?.text = topic.pub?.fn ?? "Unknown"
        return cell
    }
    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let unarchive = UITableViewRowAction(style: .normal, title: "Unarchive") { (action, indexPath) in
            print("archiving at index path")
            let topic = self.topics[indexPath.row]
            do {
                try topic.updateArchived(archived: false)?.then(onSuccess: { [weak self] msg in
                    DispatchQueue.main.async {
                        self?.reloadData()
                        self?.tableView.reloadData()
                    }
                    return nil
                })
            } catch {
                print(error)
            }
        }

        return [unarchive]
    }

    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
        if let indexPath = self.tableView.indexPathForSelectedRow {
            let messageController = segue.destination as! MessageViewController
            messageController.topicName = self.topics[indexPath.row].name
        }
    }
}
