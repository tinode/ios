//
//  MeTopic.swift
//  TinodeSDK
//
//  Copyright © 2020-2025 Tinode LLC. All rights reserved.
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

    private var credentials: [Credential]?

    public init(tinode: Tinode?, l: MeTopic<DP>.Listener? = nil) {
        super.init(tinode: tinode, name: Tinode.kTopicMe, l: l)
    }
    public init(tinode: Tinode?, desc: Description<DP, PrivateType>) {
        super.init(tinode: tinode, name: Tinode.kTopicMe, desc: desc)
    }

    override public var pinnedRank: Int? {
        get {
            return 0
        }
        set {
            // No-op: 'me' topic cannot be pinned.
        }
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
            .thenApply { [weak self] _ in
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
        return setMeta(cred: cred)
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
            return setMeta(sub: MetaSetSub(user: nil, mode: mode.description))
        }

        // The state is unchanged, return resolved promise.
        return PromisedReply<ServerMessage>(value: ServerMessage())
    }

    override internal func update(acsMap: [String: String]?, sub: MetaSetSub) {
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
        if let desc = meta.desc {
            updatePinnedTopics(priv: desc.priv)
        }

        super.update(ctrl: ctrl, meta: meta)

        if let cred = meta.cred {
            routeMetaCred(cred: cred)

            (listener as? MeTopic.Listener)?.onCredUpdated(cred: [cred])
        }
    }

    public func setMsgReadRecv(from topicName: String?, what: String?, seq: Int?) {
        guard let tn = topicName, let topic = tinode?.getTopic(topicName: tn), let seq = seq else { return }

        if seq > 0 {
            switch what {
            case Tinode.kNoteRecv:
                assignRecv(to: topic, recv: seq)
            case Tinode.kNoteRead:
                assignRead(to: topic, read: seq)
            default:
                break
            }
        }
    }

    /// Pin topic to the top of the contact list.
    ///
    /// - Parameters:
    ///  - topicName - Name of the topic to pin.
    ///  - pin - If true, pin the topic, otherwise unpin.
    ///
    /// - Returns: promise to be resolved/rejected when the server responds to request.
    public func pinTopic(topicName: String, pin: Bool) -> PromisedReply<ServerMessage> {
        if !MeTopic.isUserType(name: topicName) {
            return PromisedReply(error: TinodeError.invalidArgument("Invalid topic type to pin"))
        }

        var tpins: [String] = self.priv?.getPinnedTopics() ?? []

        let found = tpins.contains(topicName)
        if (pin && found) || (!pin && !found) {
            // Nothing to do, return resolved promise.
            return PromisedReply(value: nil)
        }

        if pin {
            // Add topic to the top of the pinned list.
            tpins.insert(topicName, at: 0)
        } else if let index = tpins.firstIndex(of: topicName) {
            // Remove topic from the pinned list.
            tpins.remove(at: index)
        }

        var newPriv = PrivateType()
        newPriv.setPinnedTopics(tpins)
        return setMeta(desc: MetaSetDesc<DP, PrivateType>(pub: nil, priv: newPriv))
    }

    /// Get the rank of the pinned topic.
    ///  - Parameters:
    ///   - topicName - name of the topic to check.
    ///
    ///  - Returns: numeric rank of the pinned topic in the range 1..N (N being the top, N - the number of pinned topics) or 0 if not pinned.
    public func pinnedTopicRank(topicName: String) -> Int {
        guard let priv = priv else {
            return 0
        }
        return priv.getPinnedRank(topicName: topicName)
    }

    private func updatePinnedTopics(priv newPriv: PrivateType?) {
        guard let newPins = newPriv?.getPinnedTopics() else {
            return
        }
        // Update pinned rank for all pinned topics.
        var rank = newPins.count
        for topicName in newPins {
            if let topic = tinode?.getTopic(topicName: topicName) {
                topic.pinnedRank = rank
                store?.topicUpdate(topic: topic)
            }
            rank -= 1
        }
        guard let thesePins = self.priv?.getPinnedTopics(), !thesePins.isEmpty else {
            return
        }
        // Unpin topics that were removed from the pinned list.
        for topicName in thesePins {
            if !newPins.contains(topicName) {
                if let topic = tinode?.getTopic(topicName: topicName) {
                    topic.pinnedRank = 0
                    store?.topicUpdate(topic: topic)
                }
            }
        }
    }

    override public func routeInfo(info: MsgServerInfo) {
        guard let what = info.what, what != Tinode.kNoteKp, let src = info.src else { return }
        if let t = tinode!.getTopic(topicName: src) as? DefaultTopic {
            t.setReadRecvByRemote(from: info.from, what: what, seq: info.seq)
        }
        // If this is an update from the current user, update the contact with the new count too.
        if tinode!.isMe(uid: info.from) {
            setMsgReadRecv(from: info.src, what: what, seq: info.seq)
        }
        listener?.onInfo(info: info)
    }

    override public func routeMeta(meta: MsgServerMeta) {
        if let cred = meta.cred {
            routeMetaCred(cred: cred)
        }

        if let desc = meta.desc as? DefaultDescription {
            updatePinnedTopics(priv: desc.priv)
            // Create or update 'me' user in storage.
            if let myUid = tinode?.myUid {
                tinode!.updateUser(uid: myUid, desc: desc)
            }
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

        if what == .kUpd {
            if Tinode.kTopicMe == pres.src {
                // Me's desc was updated, fetch the updated version.
                getMeta(query: metaGetBuilder().withDesc().build())
            } else {
                // pub/priv updated: fetch subscription update.
                getMeta(query: metaGetBuilder().withSub(userOrTopic: pres.src).build())
            }
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
                topic.setSeqAndFetch(newSeq: pres.seq)
                if pres.act == nil || tinode!.isMe(uid: pres.act!) {
                    assignRead(to: topic, read: pres.seq)
                }
                topic.touched = Date()
            case .kAcs: // access mode changed
                if pres.tgt == nil && topic.updateAccessMode(ac: pres.dacs) {
                    self.store?.topicUpdate(topic: topic)
                }
            case .kUa: // user agent changed
                topic.lastSeen = LastSeen(when: Date(), ua: pres.ua)
            case .kRecv: // user's other session marked some messages as received
                assignRecv(to: topic, recv: pres.seq)
            case .kRead: // user's other session marked some messages as read
                assignRead(to: topic, read: pres.seq)
            case .kGone:
                if topic.deleted {
                    // Alredy deleted locally: clear from DB completely.
                    topic.expunge(hard: true)
                    tinode!.stopTrackingTopic(topicName: pres.src!)
                } else {
                    // Mark as deleted.
                    topic.expunge(hard: false)
                }
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
                        getMeta(query: metaGetBuilder().withSub(userOrTopic: pres.src).build())
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

        if what == MsgServerPres.What.kGone {
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
        if let metaSubs = meta.sub as? [Subscription<DP, PrivateType>] {
            for sub in metaSubs {
                var topic = tinode!.getTopic(topicName: sub.topic!)
                let pinnedTopicRank = pinnedTopicRank(topicName: sub.topic!)
                if let topic = topic {
                    // Existing topic. Update or delete.
                    if sub.deleted != nil {
                        if topic.deleted {
                            topic.expunge(hard: true)
                            tinode!.stopTrackingTopic(topicName: sub.topic!)
                        } else {
                            topic.expunge(hard: false)
                        }
                    } else {
                        if let t = topic as? DefaultTopic {
                            t.pinnedRank = pinnedTopicRank
                            t.update(sub: sub as! Subscription<TheCard, PrivateType>)
                        } else if let t = topic as? DefaultMeTopic {
                            t.update(sub: sub as! Subscription<TheCard, PrivateType>)
                        } else {
                            Tinode.log.fault("ME.routeMetaSub - failed to update topic %@", String(describing: topic))
                            assert(false)
                        }
                    }
                } else if sub.deleted == nil {
                    // This is a new topic. Register it and write to DB.
                    // Persist will also create a user in case of a p2p topic.
                    topic = tinode!.newTopic(sub: sub)
                    topic!.pinnedRank = pinnedTopicRank
                    topic!.persist()
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
