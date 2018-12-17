//
//  ChatListAdapter.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import UIKit

class ChatListAdaper {
    var topics: [DefaultComTopic]?
    weak var tableView: UITableView?
    
    init(for tableView: UITableView?) {
        self.tableView = tableView
        resetTopics()
    }
    
    public func update() {
        resetTopics()
        tableView?.reloadData()
    }
    
    public func resetTopics() {
        topics = Cache.getTinode().getFilteredTopics(type: .user, updated: nil)?.map {
            // Must succeed.
            $0 as! DefaultComTopic
        }
    }
    
    public func topicCount() -> Int {
        return topics?.count ?? 0
    }
}
