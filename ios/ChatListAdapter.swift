//
//  ChatListAdapter.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

class ChatListAdaper {
    var topics: [DefaultComTopic]?
    
    init() {
        resetTopics()
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
