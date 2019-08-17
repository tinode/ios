//
//  StoredMessage.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

public class StoredMessage : MsgServerData, Message {
    public var msgId: Int64 = 0

    public var seqId: Int { return seq ?? 0 }

    var topicId: Int64? = nil
    var userId: Int64? = nil
    public var status: Int? = nil

    public var isDraft: Bool { get { return status == BaseDb.kStatusDraft } }
    public var isReady: Bool { get { return status == BaseDb.kStatusQueued } }
    public var isDeleted: Bool {
        get { return status == BaseDb.kStatusDeletedHard || status == BaseDb.kStatusDeletedSoft }
    }
    public func isDeleted(hard: Bool) -> Bool {
        return hard ?
            status == BaseDb.kStatusDeletedHard :
            status == BaseDb.kStatusDeletedSoft
    }
    public var isSynced: Bool { get { return status == BaseDb.kStatusSynced } }

    /// Message has not been delivered to the server yet.
    public var isPending: Bool { get { return status == nil || status! <= BaseDb.kStatusSending } }

    /// Cached representation of message content as attributed string.
    public var cachedContent: NSAttributedString?

    /// Generate and cache NSAttributedString representation of Drafty content.
    func attributedContent(fitIn size: CGSize, withDefaultAttributes attributes: [NSAttributedString.Key : Any]? = nil) -> NSAttributedString? {
        if cachedContent != nil {
            return cachedContent
        }
        guard let content = content else { return nil }
        cachedContent = AttributedStringFormatter.toAttributed(content, fitIn: size, withDefaultAttributes: attributes)
        return cachedContent
    }

    // MARK: initializers

    public override init() { super.init() }

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

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }
}
