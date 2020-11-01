//
//  MeTopic.swift
//  TinodeSDK
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import Foundation

public protocol MeTopicProto: TopicProto {
    var creds: [Credential]? { get set }
    func serializeCreds() -> String?
    @discardableResult
    func deserializeCreds(from data: String?) -> Bool
}

open class MeTopic<DP: Codable & Mergeable>: Topic<DP, PrivateType, DP, PrivateType>, MeTopicProto {
    open class Listener: Topic<DP, PrivateType, DP, PrivateType>.Listener {
        // Called when user credentials are updated.
        open func onCredUpdated(cred: [Credential]?) {}
    }

    open class MetaGetBuilder: Topic<DP, PrivateType, DP, PrivateType>.MetaGetBuilder {
        public func withCred() -> MetaGetBuilder {
            meta.setCred()
            return self
        }
    }

    private var credentials: [Credential]? = nil

    public init(tinode: Tinode?) {
        super.init(tinode: tinode, name: Tinode.kTopicMe, l: nil)
    }
    public init(tinode: Tinode?, l: MeTopic<DP>.Listener?) {
        super.init(tinode: tinode, name: Tinode.kTopicMe, l: l)
    }
    public init(tinode: Tinode?, desc: Description<DP, PrivateType>) {
        super.init(tinode: tinode, name: Tinode.kTopicMe, desc: desc)
    }

    public func serializeCreds() -> String? {
        guard let c = self.creds else { return nil }
        return Tinode.serializeObject(c)
    }
    public func deserializeCreds(from data: String?) -> Bool {
        if let c: [Credential] = Tinode.deserializeObject(from: data) {
            self.creds = c
            return true
        }
        return false
    }

    override public func metaGetBuilder() -> MetaGetBuilder {
        return MetaGetBuilder(parent: self)
    }

    override public var subsUpdated: Date? {
        return tinode?.topicsUpdated
    }

    override func loadSubs() -> Int {
        // Don't attempt to load subscriptions: 'me' subscriptions are stored as topics.
        return 0
    }

    public var creds: [Credential]? {
        get { return credentials }
        set {
            if let c = newValue {
                credentials = c.sorted(by: <)
            } else {
                credentials = nil
            }
        }
    }

    public func delCredential(meth: String, val: String) -> PromisedReply<ServerMessage> {
        return delCredential(Credential(meth: meth, val: val))
    }

    public func delCredential(_ cred: Credential) -> PromisedReply<ServerMessage> {
        let tnd = tinode!

        return tnd.delCredential(cred: cred)
            .thenApply { [weak self] msg in
                guard let me = self else { return nil }

                let idx = me.findCredIndex(cred: cred, anyUnconfirmed: false)
                if idx >= 0 {
                    me.credentials?.remove(at: idx)
                    // No need to sort.

                    me.store?.topicUpdate(topic: me)

                    // Notify listeners
                    (me.listener as! Listener).onCredUpdated(cred: me.creds)
                }
                return nil
            }
    }

    public func confirmCred(meth: String, response: String) ->PromisedReply<ServerMessage> {
        let cred = Credential(meth: meth, val: nil, resp: response, params: nil)
        return setMeta(meta: MsgSetMeta(desc: nil, sub: nil, tags: nil, cred: cred));
    }

    private func findCredIndex(cred other: Credential, anyUnconfirmed: Bool) -> Int {
        guard let creds = creds else { return -1 }
        return creds.firstIndex {
            $0.meth == other.meth && ((anyUnconfirmed && !$0.isDone) || $0.val == other.val)
        } ?? -1
    }

    override public func topicLeft(unsub: Bool?, code: Int?, reason: String?) {
        super.topicLeft(unsub: unsub, code: code, reason: reason)
        if let topics = tinode?.getTopics() {
            for t in topics {
                t.online = false
            }
        }
    }

    override public func updateMode(update: String) -> PromisedReply<ServerMessage> {
        var acs = accessMode
        if acs == nil {
           acs = Acs()
        }

        let mode = AcsHelper(ah: acs!.want)
        if mode.update(from: update) {
            return setSubscription(sub: MetaSetSub(user: nil, mode: mode.description))
        }

        // The state is unchanged, return resolved promise.
        return PromisedReply<ServerMessage>(value: ServerMessage())
    }

    override internal func update(acsMap: [String:String]?, sub: MetaSetSub) {
        var newAcs: Acs
        if let acsMap = acsMap {
            newAcs = Acs(from: acsMap)
        } else {
            newAcs = Acs()
            newAcs.want = AcsHelper(str: sub.mode)
        }

        var changed = false
        var acs = self.accessMode
        if acs == nil {
            acs = newAcs
            changed = true
        } else {
            changed = acs!.merge(from: newAcs)
        }

        if changed {
            self.accessMode = acs
            self.store?.topicUpdate(topic: self)
        }
    }

    override internal func update(ctrl: MsgServerCtrl, meta: MsgSetMeta<DP, PrivateType>) {
        super.update(ctrl: ctrl, meta: meta)
        if let cred = meta.cred {
            routeMetaCred(cred: cred)

            (listener as? MeTopic.Listener)?.onCredUpdated(cred: [cred])
        }
    }

    override public func routeMeta(meta: MsgServerMeta) {
        if let cred = meta.cred {
            routeMetaCred(cred: cred)
        }
        super.routeMeta(meta: meta)
    }

    override public func routePres(pres: MsgServerPres) {
        let what = MsgServerPres.parseWhat(what: pres.what)
        if what == .kTerm {
            // The 'me' topic itself is detached. Mark as unsubscribed.
            super.routePres(pres: pres)
            return
        }

        if what == .kUpd && Tinode.kTopicMe == pres.src {
            // Me's desc was updated, fetch the updated version.
            getMeta(query: metaGetBuilder().withDesc().build())
            return
        }

        // "what":"tags" may have src == nil
        if let topic = tinode!.getTopic(topicName: pres.src ?? "") {
            switch what {
            case .kOn: // topic came online
                topic.online = true
            case .kOff: // topic went offline
                topic.online = false
                topic.lastSeen = LastSeen(when: Date(), ua: nil)
            case .kMsg: // new message received
                topic.setSetAndFetch(newSeq: pres.seq)
                if pres.act == nil || tinode!.isMe(uid: pres.act!) {
                    assignRead(to: topic, read: pres.seq)
                }
                topic.touched = Date()
            case .kUpd: // pub/priv updated
                getMeta(query: metaGetBuilder().withSub(user: pres.src).build())
            case .kAcs: // access mode changed
                if topic.updateAccessMode(ac: pres.dacs) {
                    self.store?.topicUpdate(topic: topic)
                }
            case .kUa: // user agent changed
                topic.lastSeen = LastSeen(when: Date(), ua: pres.ua)
            case .kRecv: // user's other session marked some messages as received
                assignRecv(to: topic, recv: pres.seq)
            case .kRead: // user's other session marked some messages as read
                assignRead(to: topic, read: pres.seq)
            case .kGone:
                // If topic is unknown (==nil), then we don't care to unregister it.
                topic.persist(false)
                tinode!.stopTrackingTopic(topicName: pres.src!)
            case .kDel: // messages deleted
                // Explicitly ignored: 'me' topic has no messages.
                break
            default:
                Tinode.log.error("ME.pres message - unknown what: %@", String(describing: pres.what))
            }
        } else {
            // nil (me) or a previously unknown topic
            switch what {
            case .kAcs:
                if pres.src != nil && pres.src != Tinode.kTopicMe {
                    let acs = Acs()
                    acs.update(from: pres.dacs)
                    if acs.isModeDefined {
                        getMeta(query: metaGetBuilder().withSub(user: pres.src).build())
                    } else {
                        Tinode.log.error("ME.acs - unexpected access mode: %@", String(describing: pres.dacs))
                    }
                }
            case .kTags:
                // Account tags updated
                getMeta(query: metaGetBuilder().withTags().build())
            default:
                Tinode.log.error("ME.pres - topic not found: what = %@, src = %@",
                                 String(describing: pres.what), String(describing: pres.src))
            }
        }

        if (what == MsgServerPres.What.kGone) {
            listener?.onSubsUpdated()
        }
        listener?.onPres(pres: pres)
    }

    fileprivate func assignRecv(to topic: TopicProto, recv seq: Int?) {
        if (topic.recv ?? -1) < (seq ?? -1) {
            topic.recv = seq
            self.store?.setRecv(topic: topic, recv: seq!)
        }
    }

    fileprivate func assignRead(to topic: TopicProto, read seq: Int?) {
        if (topic.read ?? -1) < (seq ?? -1) {
            topic.read = seq
            self.store?.setRead(topic: topic, read: topic.read!)
            assignRecv(to: topic, recv: topic.read)
        }
    }

    override internal func routeMetaSub(meta: MsgServerMeta) {
        if let metaSubs = meta.sub as? Array<Subscription<DP, PrivateType>> {
            for sub in metaSubs {
                if let topic = tinode!.getTopic(topicName: sub.topic!) {
                    if sub.deleted != nil {
                        topic.persist(false)
                        tinode!.stopTrackingTopic(topicName: sub.topic!)
                    } else {
                        if let t = topic as? DefaultTopic {
                            t.update(sub: sub as! Subscription<VCard, PrivateType>)
                        } else if let t = topic as? DefaultMeTopic {
                            t.update(sub: sub as! Subscription<VCard, PrivateType>)
                        } else {
                            Tinode.log.fault("ME.routeMetaSub - failed to update topic %@", String(describing: topic))
                            assert(false)
                        }
                    }
                } else if sub.deleted == nil {
                    let topic = tinode!.newTopic(sub: sub)
                    topic.persist(true)
                }
                listener?.onMetaSub(sub: sub)
            }
        }
        listener?.onSubsUpdated()
    }

    private func processOneCred(_ cred: Credential) {
        guard cred.meth != nil else { return }

        var changed = false
        if cred.val != nil {
            if creds == nil {
                // Empty list. Create list with one new element.
                credentials = [cred]
                changed = true
            } else {
                // Try finding this credential among confirmed or not.
                var idx = findCredIndex(cred: cred, anyUnconfirmed: false)
                if idx < 0 {
                    // Not found.
                    if !cred.isDone {
                        // Unconfirmed credential replaces previous unconfirmed credential of the same method.
                        idx = findCredIndex(cred: cred, anyUnconfirmed: true)
                        if idx >= 0 {
                            // Remove previous unconfirmed credential.
                            credentials!.remove(at: idx)
                        }
                    }
                    credentials!.append(cred)
                } else {
                    // Found. Maybe change 'done' status.
                    credentials?[idx].done = cred.isDone
                }
                changed = true
            }
        } else if cred.resp != nil && credentials != nil {
            // Handle credential confirmation.
            let idx = findCredIndex(cred: cred, anyUnconfirmed: true)
            if idx >= 0 {
                credentials?[idx].done = true
                changed = true
            }
        }

        if changed {
            // Ensure predictable order.
            credentials?.sort(by: <)

            store?.topicUpdate(topic: self)
        }
    }

    internal func routeMetaCred(cred: Credential) {
        processOneCred(cred)

        (listener as? Listener)?.onCredUpdated(cred: creds)
    }

    internal func routeMetaCred(cred: [Credential]) {
        var newCreds: [Credential] = []
        for c in cred {
            if c.meth != nil && c.val != nil {
                newCreds.append(c)
            }
        }

        // Ensure predictable order of credentials.
        newCreds.sort(by: <)
        credentials = newCreds
        // Save update to DB.
        store?.topicUpdate(topic: self)
        // Notify listeners.
        (listener as? Listener)?.onCredUpdated(cred: creds)
    }
}
