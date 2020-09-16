//
//  ComTopic.swift
//  TinodeSDK
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import Foundation

public class ComTopic<DP: Codable & Mergeable>: Topic<DP, PrivateType, DP, PrivateType> {
    override init(tinode: Tinode?, name: String, l: Listener?) {
        super.init(tinode: tinode, name: name, l: l)
    }
    override init(tinode: Tinode?, sub: Subscription<DP, PrivateType>) {
        super.init(tinode: tinode, sub: sub)
    }
    override init(tinode: Tinode?, name: String, desc: Description<DP, PrivateType>) {
        super.init(tinode: tinode, name: name, desc: desc)
    }
    public convenience init(in tinode: Tinode?, forwardingEventsTo l: Listener? = nil, isChannel: Bool) {
        let name = (isChannel ? Tinode.kChannelNew : Tinode.kTopicNew) + tinode!.nextUniqueString()
        self.init(tinode: tinode!, name: name, l: l)
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

    public var peer: Subscription<DP, PrivateType>? {
        guard isP2PType else { return nil }
        return self.getSubscription(for: self.name)
    }

    override public func getSubscription(for key: String?) -> Subscription<DP, PrivateType>? {
        guard let sub = super.getSubscription(for: key) else { return nil }
        if isP2PType && sub.pub == nil {
            sub.pub = self.name == key ? self.pub : tinode?.getMeTopic()?.pub as? DP
        }
        return sub
    }

    public func updateArchived(archived: Bool) -> PromisedReply<ServerMessage>? {
        var priv = PrivateType()
        priv.archived = archived
        let meta = MsgSetMeta<DP, PrivateType>(
            desc: MetaSetDesc(pub: nil, priv: priv),
            sub: nil,
            tags: nil,
            cred: nil)
        return setMeta(meta: meta)
    }
}
