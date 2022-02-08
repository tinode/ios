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

    public override var isArchived: Bool {
        guard let archived = priv?["arch"] else { return false }
        switch archived {
        case .bool(let x):
            return x
        default:
            return false
        }
    }

    public var isChannel: Bool {
        return ComTopic.isChannel(name: name)
    }

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
}
