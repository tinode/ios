//
//  ComTopic.swift
//  TinodeSDK
//
//  Copyright © 2020-2022 Tinode LLC. All rights reserved.
//

import Foundation

public class ComTopic: Topic<TheCard, PrivateType, TheCard, PrivateType> {
    public convenience init(in tinode: Tinode?, forwardingEventsTo l: Listener? = nil, isChannel: Bool) {
        let name = (isChannel ? Tinode.kChannelNew : Tinode.kTopicNew) + tinode!.nextUniqueString()
        self.init(tinode: tinode!, name: name, l: l)
    }

    @discardableResult
    public override func subscribe() -> PromisedReply<ServerMessage> {
        if isNew {
            let desc = MetaSetDesc(pub: self.pub, priv: self.priv)
            if let pub = self.pub {
                desc.attachments = pub.photoRefs
            }
            return subscribe(set: MsgSetMeta(desc: desc, sub: nil, tags: self.tags, cred: nil), get: nil)
        }
        return super.subscribe()
    }

    public override func routeData(data: MsgServerData) {
        if let head = data.head, let content = data.content,
           head["webrtc"]?.asString() != nil,
           let mime = head["mime"]?.asString(), mime == Drafty.kMimeType {
            // If it's a video call,
            // rewrite VC body with info from the headers.
            let outgoing = (!self.isChannel && data.from == nil) || (self.tinode?.isMe(uid: data.from) ?? false)
            content.updateVideoEnt(withParams: head, isIncoming: !outgoing)
        }
        super.routeData(data: data)
    }

    /// Check if the topic is archived.
    public override var isArchived: Bool {
        guard let archived = priv?["arch"] else { return false }
        switch archived {
        case .bool(let x):
            return x
        default:
            return false
        }
    }

    /// Check if the topic is a channel.
    public var isChannel: Bool {
        return ComTopic.isChannel(name: name)
    }

    /// Check if the given topic name is a name of a channel.
    public static func isChannel(name: String) -> Bool {
        return name.starts(with: Tinode.kTopicChnPrefix)
    }

    public var comment: String? {
        return priv?.comment
    }

    public var peer: Subscription<TheCard, PrivateType>? {
        guard isP2PType else { return nil }
        return self.getSubscription(for: self.name)
    }

    override public func getSubscription(for key: String?) -> Subscription<TheCard, PrivateType>? {
        guard let sub = super.getSubscription(for: key) else { return nil }
        if isP2PType && sub.pub == nil {
            sub.pub = self.name == key ? self.pub : tinode?.getMeTopic()?.pub
        }
        return sub
    }

    /// Send message to server that the topic is archived or un-archived.
    /// - Parameters:
    ///   - param: archived `true` to archive the topic, `false` to un-archive.
    /// - Returns: PromisedReply of the reply ctrl message
    public func updateArchived(archived: Bool) -> PromisedReply<ServerMessage>? {
        var priv = PrivateType()
        priv.archived = archived
        let meta = MsgSetMeta<TheCard, PrivateType>(
            desc: MetaSetDesc(pub: nil, priv: priv),
            sub: nil,
            tags: nil,
            cred: nil)
        return setMeta(meta: meta)
    }

    /// First read messages from the local cache. If cache does not contain enough messages, fetch more from the server.
    /// - Parameters:
    ///    - startWithSeq: the seq ID of the message to start loading from (exclusive); if `startWithSeq` is greater than the maximum seq value or less than 1, then use max seq value or 1 respectively.
    ///    - pageSize: number of messages to fetch.
    ///    - forward: load newer messages if `true`, older if `false`.
    ///    - onLoaded: callback which receives loaded messages and an error.
    public func loadMessagePage(startWithSeq: Int, pageSize limit: Int, forward: Bool, onLoaded: @escaping ([Message]?, Error?) -> Void) {
        if limit <= 0 || self.seq == nil || self.seq! == 0 {
            // Invalid limit or topic has no messages.
            onLoaded([], nil)
        }

        // Sanitize 'from'.
        let from = forward ? max(0, startWithSeq) : min(self.seq! + 1, startWithSeq)

        // TODO: check if cache has enough messages to fullfill the request. If not, don't query the DB, fetch delta from the server right away, then fetch all needed messages from DB.
        // let range = store?.getCachedMessagesRange(topic: self)

        // First try fetching from DB, then from the server.
        let messages = store?.getMessagePage(topic: self, from: from, limit: limit, forward: forward)
        let remainingCount = limit - (messages?.count ?? 0)
        if remainingCount <= 0 {
            // Request is fulfilled with cached messages.
            onLoaded(messages, nil)
            return
        }

        // ID of the last message loaded from DB.
        let lastLoadedSeq = messages?.last?.seqId ?? from
        if !self.attached || (forward && lastLoadedSeq == self.seq!) || (!forward && lastLoadedSeq == 1) {
            // All messages are loaded, nothing to fetch from the server or not attached.
            onLoaded(messages, nil)
            return
        }

        // Not enough messages in cache to fullfill the request, call the server.

        // Use query builder to get cached message ranges.
        let query = metaGetBuilder().withEarlierData(limit: limit)
        getMeta(query: query.build())
            .thenApply({ _ in
                // Read message page from DB.
                let messages = self.store?.getMessagePage(topic: self, from: from, limit: limit, forward: forward)
                onLoaded(messages, nil)
                return nil
            })
            .thenCatch({ err in
                onLoaded(nil, err)
                return nil
            })
    }
}
