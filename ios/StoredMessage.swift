//
//  StoredMessage.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

class StoredMessage : MsgServerData, Message {
    var msgId: Int64 = 0
    
    var seqId: Int { return seq ?? 0 }

    //var id: Int64? = nil
    var topicId: Int64? = nil
    var userId: Int64? = nil
    public var status: Int? = nil

    // Get current message payload.
    //var content: Any? { get { return self.content } }
    // Get current message unique ID (database ID).
    //var id: Int64
    
    // Get Tinode seq Id of the message (different from database ID).
    //var seqId: Int { get }
    
    var isDraft: Bool { get { return status == 1 } }
    var isReady: Bool { get { return status == 2 } }
    var isDeleted: Bool { get { return status == 4 || status == 5 } }
    func isDeleted(hard: Bool) -> Bool {
        return hard ?
            status == 4 :
            status == 5
    }
    var isSynced: Bool { get { return status == 3 } }
    
    convenience init(from m: MsgServerData) {
        self.init()
        self.topic = m.topic
        self.head = m.head
        self.from = m.from
        self.ts = m.ts
        self.seq = m.seq
        self.content = m.content
    }
    convenience init(from m: MsgServerData, status: Int) {
        self.init(from: m)
        self.status = status
    }
}
