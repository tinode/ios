//
//  Storage.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

protocol Message {
    // Get current message payload.
    var content: Any? { get }
    // Get current message unique ID (database ID).
    var id: Int64 { get }

    // Get Tinode seq Id of the message (different from database ID).
    var seqId: Int { get }

    var isDraft: Bool { get }
    var isReady: Bool { get }
    var isDeleted: Bool { get }
    func isDeleted(hard: Bool) -> Bool
    var isSynced: Bool { get }
}

protocol MessageIterator {
    func next() -> Message?
}

// Base protocol for implementing persistance.
protocol Storage {
    // Min and max values.
    typealias Range = (min: Int, max: Int)

    var myUid: String { get set }

    var deviceToken: String { get set }

    func logout()

    // Server time minus local time.
    func setTimeAdjustment(adjustment: Int64)

    var isReady: Bool { get }

    // Fetch all topics.
    func topicGetAll(from tinode: Tinode?) -> [String]?
    // Add new topic.
    func topicAdd(topic: TopicProto) -> Int64
    // Incoming change to topic description:
    // the already mutated topic in memory is synchronized to DB.
    func topicUpdate(topic: TopicProto) -> Bool
    // Delete topic.
    func topicDelete(topic: TopicProto) -> Bool

    // Get seq IDs of the stored messages as a Range.
    func getCachedMessagesRange(topic: TopicProto) -> Range
    // Local user reported messages as read.
    func setRead(topic: TopicProto, read: Int) -> Bool
    // Local user reported messages as received.
    func setRecv(topic: TopicProto, recv: Int) -> Bool

    // Add subscription in a generic topic.
    // The subscription is received from the server.
    func subAdd(topic: TopicProto, sub: SubscriptionProto) -> Int64
    // Update subscription in a generic topic.
    func subUpdate(topic: TopicProto, sub: SubscriptionProto) -> Bool
    // Add a new subscriber to topic.
    // The new subscriber is being added locally.
    func subNew(topic: TopicProto, sub: SubscriptionProto) -> Int64
    // Delete existing subscription.
    func subDelete(topic: TopicProto, sub: SubscriptionProto) -> Bool

    // Get a list o topic subscriptions from DB.
    func getSubscriptions(topic: TopicProto) -> [SubscriptionProto]?

    // Read user description.
    func userGet(uid: String) -> UserProto?
    // Insert new user.
    func userAdd(user: UserProto) -> Int64
    // Update existing user.
    func userUpdate(user: UserProto) -> Bool

    // Message received from the server.
    func msgReceived(topic: TopicProto, sub: SubscriptionProto, msg: MsgServerData) -> Int64

    // Save message to DB as queued or synced.
    // Params:
    //   topic: topic which sent the message.
    //   data: message data to save.
    // Returns:
    //   database ID of the message suitable for use in.
    func msgSend(topic: TopicProto, data: Drafty) -> Int64

    // Save message to database as a draft.
    // Draft will not be sent to server until it status changes.
    // Params:
    //   topic: topic which sent the message.
    //   data: message data to save.
    // Returns:
    //   database ID of the message suitable for use in
    func msgDraft(topic: TopicProto, data: Drafty) -> Int64

    // Update message draft content without
    // Params:
    //   topic: topic which sent the message.
    //   dbMessageId: database ID of the message.
    //   data: updated content of the message. Must not be null.
    // Returns true on success, false otherwise.
    func msgDraftUpdate(topic: TopicProto, dbMessageId: Int64, data: Drafty) -> Bool

    // Message is ready to be sent to the server.
    // Params:
    //   topic: topic which sent the message
    //   dbMessageId: database ID of the message.
    //   data: updated content of the message. If null only status is updated.
    // Returns true on success, false otherwise.
    func msgReady(topic: TopicProto, dbMessageId: Int64, data: Drafty) -> Bool

    // Deletes a message by database id.
    func msgDiscard(topic: TopicProto, dbMessageId: Int64) -> Bool

    // Message delivered to the server and received a real seq ID.
    // Params:
    //   topic: topic which sent the message.
    //   dbMessageId: database ID of the message.
    //   timestamp: server timestamp.
    //   seq: server-issued message seqId.
    // Returns true on success, false otherwise.
    func msgDelivered(topic: TopicProto, dbMessageId: Int64,
                      timestamp: Date, seq: Int) -> Bool
    // Mark messages for deletion by range.
    func msgMarkToDelete(topic: TopicProto,
                         from idLo: Int, to idHi: Int, markAsHard: Bool) -> Bool
    // Mark messages for deletion by seq ID list.
    func msgMarkToDelete(topic: TopicProto, list: [Int], markAsHard: Bool) -> Bool
    // Delete messages.
    func msgDelete(topic: TopicProto, delete id: Int,
                   deleteFrom idLo: Int, deleteTo idHi: Int) -> Bool
    // Delete messages.
    func msgDelete(topic: TopicProto, delete id: Int, deleteAll list: [Int]?) -> Bool
    // Set recv value for a given subscriber.
    func msgRecvByRemote(sub: SubscriptionProto, recv: Int) -> Bool
    // Set read value for a given subscriber.
    func msgReadByRemote(sub: SubscriptionProto, read: Int) -> Bool

    // Retrieves a single message by database id.
    func getMessageById(topic: TopicProto, dbMessageId: Int64) -> Message

    // Gets a list of unsent messages.
    func getQueuedMessages(topic: TopicProto) -> MessageIterator?
}
