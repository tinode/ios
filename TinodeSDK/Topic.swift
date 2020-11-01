//
//  Topic.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

public protocol Payload: class {
}

public protocol TopicProto: class {
    var name: String { get }
    var updated: Date? { get set }
    var touched: Date? { get set }
    var subsUpdated: Date? { get }
    var topicType: TopicType { get }
    var maxDel: Int { get set }
    var store: Storage? { get set }
    var isPersisted: Bool { get }
    var read: Int? { get set }
    var recv: Int? { get set }
    var seq: Int? { get set }
    var clear: Int? { get set }
    var payload: Payload? { get set }
    var tags: [String]? { get set }
    var isNew: Bool { get }
    var accessMode: Acs? { get set }
    var defacs: Defacs? { get set }
    var lastSeen: LastSeen? { get set }
    var online: Bool { get set }
    var cachedMessageRange: MsgRange? { get }
    var missingMessageRange: MsgRange? { get }
    var isArchived: Bool { get }
    var isJoiner: Bool { get }
    var isBlocked: Bool { get }
    var isReader: Bool { get }
    var isMuted: Bool { get }
    var unread: Int { get }

    func serializePub() -> String?
    func serializePriv() -> String?
    @discardableResult
    func deserializePub(from data: String?) -> Bool
    @discardableResult
    func deserializePriv(from data: String?) -> Bool
    func topicLeft(unsub: Bool?, code: Int?, reason: String?)

    func updateAccessMode(ac: AccessChange?) -> Bool
    func persist(_ on: Bool)
    func setSetAndFetch(newSeq: Int?)

    func allMessagesReceived(count: Int?)
    func allSubsReceived()
    func routeMeta(meta: MsgServerMeta)
    func routeData(data: MsgServerData)
    func routePres(pres: MsgServerPres)
    func routeInfo(info: MsgServerInfo)
}

public enum TopicType: Int {
    case me = 0x01
    case fnd = 0x02
    case grp = 0x04
    case p2p = 0x08
    case user = 0x0c // .grp | .p2p
    case system = 0x03 // .me | .fnd
    case unknown = 0x00
    case any = 0x0f // .user | .system

    public func matches(_ t2: TopicType) -> Bool {
        return (self.rawValue & t2.rawValue) != 0
    }
}

// Cannot make it a class constant because Swift is poorly designed: "Static stored properties not supported in generic types"
fileprivate let kIntervalBetweenKeyPresses: TimeInterval = 3.0

open class Topic<DP: Codable & Mergeable, DR: Codable & Mergeable, SP: Codable, SR: Codable>: TopicProto {
    enum TopicError: Error {
        case alreadySubscribed
        case notSynchronized
        case subscriptionFailure(String)
    }

    enum NoteType {
        case kRead
        case kRecv
        case kKeyPress
    }

    open class Listener {
        public init() {}
        open func onSubscribe(code: Int, text: String) {}
        open func onLeave(unsub: Bool?, code: Int?, text: String?) {}

        // Process {data} message.
        open func onData(data: MsgServerData?) {}
        // All requested data messages received.
        open func onAllMessagesReceived(count: Int) {}

        // {info} message received.
        open func onInfo(info: MsgServerInfo) {}
        // {meta} message received.
        open func onMeta(meta: MsgServerMeta) {}
        // {meta what="sub"} message received, and this is one of the subs.
        open func onMetaSub(sub: Subscription<SP, SR>) {}
        // {meta what="desc"} message received.
        open func onMetaDesc(desc: Description<DP, DR>) {}
        // {meta what="tags"} message received.
        open func onMetaTags(tags: [String]) {}
        // {meta what="sub"} message received and all subs were processed.
        open func onSubsUpdated() {}
        // {pres} received.
        open func onPres(pres: MsgServerPres) {}
        // {pres what="on|off"} is received.
        open func onOnline(online: Bool) {}
        // Topic descriptor as contact is updated.
        open func onContUpdate(sub: Subscription<SP, SR>) {}
    }

    open class MetaGetBuilder {
        let topic: TopicProto
        var meta: MsgGetMeta

        init(parent: TopicProto) {
            self.topic = parent
            self.meta = MsgGetMeta()
        }

        public func withData(since: Int?, before: Int?, limit: Int?) -> MetaGetBuilder {
            meta.setData(since: since, before: before, limit: limit)
            return self
        }
        public func withEarlierData(limit: Int?) -> MetaGetBuilder {
            if let r = topic.missingMessageRange, r.low >= 1 {
                return withData(since: r.lower, before: r.upper, limit: limit)
            }
            return withData(since: nil, before: nil, limit: limit)
        }
        public func withLaterData(limit: Int?) -> MetaGetBuilder {
            if let r = topic.cachedMessageRange {
                return withData(since: r.hi != 0 ? r.hi : nil, before: nil, limit: limit)
            }
            return withData(since: nil, before: nil, limit: limit)
        }
        public func withData() -> MetaGetBuilder {
            return withLaterData(limit: nil)
        }

        public func withDel(since: Int?, limit: Int?) -> MetaGetBuilder {
            meta.setDel(since: since, limit: limit)
            return self
        }
        public func withLaterDel(limit: Int?) -> MetaGetBuilder {
            return withDel(since: topic.maxDel > 0 ? topic.maxDel + 1 : nil, limit: limit)
        }
        public func withDel() -> MetaGetBuilder {
            return withLaterDel(limit: nil)
        }

        public func withDesc() -> MetaGetBuilder {
            return withDesc(ims: topic.updated)
        }
        public func withDesc(ims: Date?) -> MetaGetBuilder {
            meta.setDesc(ims: ims)
            return self
        }
        public func withSub(user: String?, ims: Date?, limit: Int?) -> MetaGetBuilder {
            meta.setSub(user: user, ims: ims, limit: limit)
            return self
        }
        public func withSub(user: String?) -> MetaGetBuilder {
            return withSub(user: user, ims: topic.subsUpdated, limit: nil)
        }

        public func withSub(ims: Date?, limit: Int?) -> MetaGetBuilder {
            return withSub(user: nil, ims: ims, limit: limit)
        }
        public func withSub() -> MetaGetBuilder {
            return withSub(user: nil, ims: topic.subsUpdated, limit: nil)
        }
        public func withTags() -> MetaGetBuilder {
            meta.setTags()
            return self
        }
        public func build() -> MsgGetMeta {
            return meta
        }
    }

    internal weak var tinode: Tinode? = nil
    public var name: String = ""
    public var isNew: Bool {
        return Topic.isNewByName(name: name)
    }

    public var updated: Date? {
        get {
            return description?.updated
        }
        set {
            if let nv = newValue, nv > (description?.updated ?? Date.distantPast) {
                description?.updated = nv
            }
        }
    }

    public var touched: Date? {
        get {
            return description?.touched
        }
        set {
            if let nv = newValue, nv > (description?.touched ?? Date.distantPast) {
                description?.touched = nv
            }
        }
    }

    public var read: Int? {
        get {
            return description?.read
        }
        set {
            if (newValue ?? -1) > (description?.read ?? -1) {
                description?.read = newValue
            }
        }
    }

    public var recv: Int? {
        get {
            return description?.recv
        }
        set {
            if (newValue ?? -1) > (description?.recv ?? -1) {
                description?.recv = newValue
            }
        }
    }

    public var seq: Int? {
        get {
            return description?.seq
        }
        set {
            if (newValue ?? -1) > (description?.seq ?? -1) {
                description?.seq = newValue
            }
        }
    }

    public var clear: Int? {
        get {
            return description?.clear
        }
        set {
            if (newValue ?? -1) > (description?.clear ?? -1) {
                description?.clear = newValue
            }
        }
    }

    public var unread: Int {
        let unread = (description?.seq ?? 0) - (description?.read ?? 0)
        return unread > 0 ? unread : 0
    }

    public var subsLastUpdated: Date? = nil
    public var subsUpdated: Date? {
        return subsLastUpdated
    }
    public var accessMode: Acs? {
        get { return description?.acs }
        set { description?.acs = newValue }
    }
    public var defacs: Defacs? {
        get { return description?.defacs }
        set { description?.defacs = newValue }
    }

    // The bulk of topic data
    private var description: Description<DP, DR>? = nil
    public var pub: DP? {
        get { return description?.pub }
        set { description?.pub = newValue }
    }
    public var priv: DR? {
        get { return description?.priv }
        set { description?.priv = newValue }
    }
    public var attached = false
    weak public var listener: Listener? = nil
    // Cache of topic subscribers indexed by userID
    internal var subs: [String:Subscription<SP,SR>]? = nil
    public var tags: [String]? = nil
    private var lastKeyPress: Date = Date(timeIntervalSince1970: 0)

    public var online: Bool = false {
        didSet {
            if oldValue != online {
                listener?.onOnline(online: online)
            }
        }
    }

    public var lastSeen: LastSeen? = nil

    public var maxDel: Int = 0 {
        didSet {
            if maxDel < oldValue {
                maxDel = oldValue
            }
        }
    }

    public var topicType: TopicType {
        return Tinode.topicTypeByName(name: self.name)
    }
    public var isP2PType: Bool {
        return topicType == .p2p
    }
    public var isMeType: Bool {
        return topicType == .me
    }
    public var isFndType: Bool {
        return topicType == .fnd
    }
    public var isGrpType: Bool {
        return topicType == .grp
    }
    public var isManager: Bool {
        return description?.acs?.isManager ?? false
    }
    public var isSharer: Bool {
        return description?.acs?.isSharer ?? false
    }
    public var isMuted: Bool {
        return description?.acs?.isMuted ?? false
    }
    public var isOwner: Bool {
        return description?.acs?.isOwner ?? false
    }
    public var isAdmin: Bool {
        return description?.acs?.isAdmin ?? false
    }
    public var isReader: Bool {
        return description?.acs?.isReader ?? false
    }
    public var isWriter: Bool {
        return description?.acs?.isWriter ?? false
    }
    public var isJoiner: Bool {
        return description?.acs?.isJoiner ?? false
    }
    public var isBlocked: Bool {
        return !(description?.acs?.isJoiner(for: Acs.Side.given) ?? false)
    }
    public var isDeleter: Bool {
        return description?.acs?.isDeleter ?? false
    }
    public var isArchived: Bool {
        return false
    }

    // Returns the maximum recv and read values across all subscriptions
    // that are not "me" (this user).
    public var maxRecvReadValues: (Int, Int) {
        if subs == nil {
            loadSubs()
        }

        guard let subs = subs, let me = tinode?.myUid else { return (0, 0) }
        var maxRecv = 0, maxRead = 0
        for (key, sub) in subs {
            if key != me {
                maxRead = max(maxRead, sub.getRead)
                maxRecv = max(maxRecv, sub.getRecv)
            }
        }
        return (maxRecv, maxRead)
    }

    // Storage is owned by Tinode.
    weak public var store: Storage? = nil
    public var payload: Payload? = nil
    public var isPersisted: Bool { get { return payload != nil } }

    public var cachedMessageRange: MsgRange? {
        return store?.getCachedMessagesRange(topic: self)
    }

    public var missingMessageRange: MsgRange? {
        return store?.getNextMissingRange(topic: self)
    }

    // Tells how many topic subscribers have reported the message as read or received.
    internal func msgReadRecvCount(seq: Int?, read: Bool) -> Int {
        if subs == nil {
            loadSubs()
        }

        guard let subs = subs, let me = tinode?.myUid, let seq = seq, seq > 0 else { return 0 }
        return  subs.reduce(0, { (count, tuple) -> Int in
            let (key, sub) = tuple
            if key != me && (read ? sub.getRead : sub.getRecv) >= seq {
                return count + 1
            }
            return count
        } )
    }

    // Tells how many topic subscribers have reported the message as read.
    public func msgReadCount(seq: Int?) -> Int {
        return msgReadRecvCount(seq: seq, read: true)
    }

    // Tells how many topic subscribers have reported the message as received.
    public func msgRecvCount(seq: Int?) -> Int {
        return msgReadRecvCount(seq: seq, read: false)
    }

    init() {}

    /**
     * Workaround for the  init() - convenience init() madness.
     */
    private func superInit(tinode: Tinode?, name: String, l: Listener? = nil) {
        self.tinode = tinode
        self.name = name
        self.description = Description()
        self.listener = l

        if tinode != nil {
            tinode!.startTrackingTopic(topic: self)
        }
    }

    init(tinode: Tinode?, name: String, l: Listener? = nil) {
        self.superInit(tinode: tinode, name: name, l: l)
    }
    init(tinode: Tinode?, sub: Subscription<SP, SR>) {
        self.superInit(tinode: tinode, name: sub.topic!)
        _ = self.description!.merge(sub: sub)

        if sub.online != nil {
            self.online = sub.online!
        }
    }
    init(tinode: Tinode?, name: String, desc: Description<DP, DR>) {
        self.superInit(tinode: tinode, name: name)
        _ = self.description!.merge(desc: desc)
    }

    public static func isNewByName(name: String) -> Bool {
        return name.starts(with: Tinode.kTopicNew) || name.starts(with: Tinode.kChannelNew)
    }
    private func setName(name: String) {
        self.name = name
    }
    public func serializePub() -> String? {
        guard let p = pub else { return nil }
        return Tinode.serializeObject(p)
    }
    public func serializePriv() -> String? {
        guard let p = priv else { return nil }
        return Tinode.serializeObject(p)
    }
    public func deserializePub(from data: String?) -> Bool {
        if let p: DP = Tinode.deserializeObject(from: data) {
            description?.pub = p
            return true
        }
        return false
    }
    public func deserializePriv(from data: String?) -> Bool {
        if let p: DR = Tinode.deserializeObject(from: data) {
            description?.priv = p
            return true
        }
        return false
    }

    public func metaGetBuilder() -> MetaGetBuilder {
        // Ensure the topic is fully initialized before any get requests are issued.
        if subs == nil {
            loadSubs()
        }
        return MetaGetBuilder(parent: self)
    }

    public func persist(_ on: Bool) {
        if on {
            if !isPersisted {
                store?.topicAdd(topic: self)
            }
        } else {
            store?.topicDelete(topic: self)
        }
    }

    @discardableResult
    public func subscribe() -> PromisedReply<ServerMessage> {
        var setMsg: MsgSetMeta<DP, DR>? = nil
        var getMsg: MsgGetMeta? = nil
        if isNew {
            setMsg = MsgSetMeta<DP, DR>(
                desc: MetaSetDesc(pub: self.pub, priv: self.priv),
                sub: nil,
                tags: self.tags, cred: nil)
        } else {
            getMsg = metaGetBuilder()
                .withDesc().withData().withSub().withTags().build()
        }
        return subscribe(set: setMsg, get: getMsg)
    }

    @discardableResult
    public func subscribe(set: MsgSetMeta<DP, DR>?, get: MsgGetMeta?) -> PromisedReply<ServerMessage> {
        if attached {
            // If the topic is already attached and the user
            // does not attempt to set or get any data,
            // just return resolved promise.
            if set == nil && get == nil {
                return PromisedReply(value: ServerMessage())
            }
            return PromisedReply(error: TopicError.alreadySubscribed)
        }
        let name = self.name
        if !isPersisted {
            persist(true)
        }
        let tnd = tinode!
        guard tnd.isConnected else {
            return PromisedReply(error: TinodeError.notConnected("Cannot subscribe to topic. No server connection."))
        }
        guard tnd.isConnectionAuthenticated else {
            return PromisedReply(error: TinodeError.invalidState("Connection is not authenticated.") )
        }
        return tnd.subscribe(to: name, set: set, get: get).then(
            onSuccess: { [weak self] msg in
                if let code = msg?.ctrl?.code, code >= 300 {
                    // 3XX: status unchanged.
                    return nil
                }
                let isAttached = self?.attached ?? false
                if !isAttached {
                    self?.attached = true
                    if let ctrl = msg?.ctrl {
                        if !(ctrl.params?.isEmpty ?? true) {
                            self?.description?.acs = Acs(from: ctrl.getStringDict(for: "acs"))
                            if self?.isNew ?? false {
                                self?.updated = ctrl.ts
                                self?.setName(name: ctrl.topic!)
                                _ = self?.tinode?.changeTopicName(topic: self!, oldName: name)
                            }
                            // update store
                            self?.store?.topicUpdate(topic: self!)
                        }
                        self?.listener?.onSubscribe(code: ctrl.code, text: ctrl.text)
                    }
                }
                return nil
            },
            onFailure: { [weak self] err in
                if let e = err as? TinodeError, (self?.isNew ?? false),
                    case TinodeError.serverResponseError(let code, _, _) = e {
                    if ServerMessage.kStatusBadRequest <= code && code < ServerMessage.kStatusInternalServerError {
                        self?.tinode?.stopTrackingTopic(topicName: name)
                        self?.persist(false)
                    }
                }
                // To next handler.
                throw err
            })
    }

    public func allMessagesReceived(count: Int?) {
        listener?.onAllMessagesReceived(count: count ?? 0)
    }

    public func allSubsReceived() {
        listener?.onSubsUpdated()
    }

    @discardableResult internal func loadSubs() -> Int {
        guard let loaded = store?.getSubscriptions(topic: self) else { return 0 }
        subsLastUpdated = loaded.max(by: {(s1, s2) -> Bool in
            ((s1.updated ?? Date.distantPast) < (s2.updated ?? Date.distantPast))
        })?.updated
        subs = (Dictionary(uniqueKeysWithValues: loaded.map { ($0.user, $0) }) as! [String : Subscription<SP, SR>])
        return subs!.count
    }

    public func getSubscription(for key: String?) -> Subscription<SP, SR>? {
        if subs == nil {
            loadSubs()
        }
        if let k = key {
            return subs != nil ? subs![k] : nil
        } else {
            return nil
        }
    }
    public func getSubscriptions() -> [Subscription<SP, SR>]? {
        if subs == nil {
            loadSubs()
        }
        if let v = subs?.values {
            return Array(v)
        }
        return nil
    }

    private func routeMetaDesc(meta: MsgServerMeta) {
        update(desc: meta.desc as! Description<DP, DR>)
        if case .p2p = topicType {
            tinode?.updateUser(uid: name, desc: meta.desc as! DefaultDescription)
        }
        // update listener
        listener?.onMetaDesc(desc: (meta.desc as! Description<DP, DR>))
    }
    private func removeSubFromCache(sub: Subscription<SP, SR>) {
        subs?.removeValue(forKey: sub.user!)
    }

    internal func update(sub: Subscription<SP, SR>) {
        var changed = false
        if self.lastSeen == nil {
            self.lastSeen = sub.seen
            changed = true
        } else {
            changed = self.lastSeen!.merge(seen: sub.seen)
        }
        if description?.merge(sub: sub) ?? false, changed {
            store?.topicUpdate(topic: self)
        }
        if let o = sub.online {
            self.online = o
        }
    }
    internal func update(desc: Description<DP, DR>) {
        if description?.merge(desc: desc) ?? false {
            store?.topicUpdate(topic: self)
        }
    }
    internal func update(tags: [String]) {
        self.tags = tags
        store?.topicUpdate(topic: self)
    }
    internal func update(desc: MetaSetDesc<DP, DR>) {
        if self.description?.merge(desc: desc) ?? false {
            self.store?.topicUpdate(topic: self)
        }
    }
    // Topic sent an update to description or subscription, got a confirmation, now
    // update local data with the new info.
    internal func update(ctrl: MsgServerCtrl, meta: MsgSetMeta<DP, DR>) {
        if let desc = meta.desc {
            self.update(desc: desc)
            if let d = self.description {
                self.listener?.onMetaDesc(desc: d)
            }
        }
        if let sub = meta.sub {
            let acsMap = ctrl.getStringDict(for: "acs")
            self.update(acsMap: acsMap, sub: sub)
            if sub.user == nil, let description = self.description {
                self.listener?.onMetaDesc(desc: description)
            }
            self.listener?.onSubsUpdated()
        }
        if let tags = meta.tags {
            self.update(tags: tags)
            self.listener?.onMetaTags(tags: tags)
        }
    }
    internal func update(acsMap: [String:String]?, sub: MetaSetSub) {
        var user = sub.user
        var acs: Acs
        if let acsMap = acsMap {
            acs = Acs(from: acsMap)
        } else {
            acs = Acs()
            if user == nil {
                acs.want = AcsHelper(str: sub.mode)
            } else {
                acs.given = AcsHelper(str: sub.mode)
            }
        }

        if user == nil || (tinode?.isMe(uid: user) ?? false) {
            user = tinode?.myUid
            var changed = false
            if self.description?.acs == nil {
                self.description?.acs = acs
                changed = true
            } else {
                self.description!.acs!.merge(from: acs)
            }
            if changed {
                self.store?.topicUpdate(topic: self)
            }
        }
        if let sub2 = self.getSubscription(for: user) {
            sub2.acs?.merge(from: acs)
            store?.subUpdate(topic: self, sub: sub2)
        } else {
            let sub2 = Subscription<SP, SR>()
            sub2.user = user
            sub2.acs = acs
            self.addSubToCache(sub: sub2)
            _ = self.store?.subNew(topic: self, sub: sub2)
        }
    }
    internal func addSubToCache(sub: Subscription<SP, SR>) {
        guard let user = sub.user else { return }

        if subs == nil {
            subs = [:]
        }
        subs![user] = sub
    }

    private func processSub(newsub: Subscription<SP, SR>) {
        var sub: Subscription<SP, SR>?
        if (newsub.deleted != nil) {
            store?.subDelete(topic: self, sub: newsub)
            removeSubFromCache(sub: newsub)

            sub = newsub
        } else {
            guard let user = newsub.user else {
                Tinode.log.error("Subscription missing user field (topic %@), uniqueId: %@", self.name, newsub.uniqueId ?? "NONE")
                return
            }
            sub = getSubscription(for: user)
            if sub != nil {
                _ = sub!.merge(sub: newsub)
                store?.subUpdate(topic: self, sub: sub!)
            } else {
                sub = newsub
                addSubToCache(sub: sub!)
                store?.subAdd(topic: self, sub: sub!)
            }
            tinode!.updateUser(sub: sub!)
        }
        listener?.onMetaSub(sub: sub!)
    }
    private func routeMetaDel(clear: Int, delseq: [MsgRange]) {
        store?.msgDelete(topic: self, delete: clear, deleteAllIn: delseq)
        self.maxDel = clear
        listener?.onData(data: nil)
    }

    internal func routeMetaSub(meta: MsgServerMeta) {
        if let metaSubs = meta.sub as? Array<Subscription<SP, SR>> {
            for newsub in metaSubs {
                processSub(newsub: newsub)
            }
        }
        // update listener
        listener?.onSubsUpdated()
    }
    private func routeMetaTags(tags: [String]) {
        self.update(tags: tags)
        listener?.onMetaTags(tags: tags)
    }

    public func routeMeta(meta: MsgServerMeta) {
        if meta.desc != nil {
            routeMetaDesc(meta: meta)
        }
        if meta.sub != nil {
            if subsUpdated == nil || (meta.ts != nil && subsUpdated! < meta.ts!) {
                subsLastUpdated = meta.ts!
            }
            self.routeMetaSub(meta: meta)
        }
        if meta.del != nil {
            routeMetaDel(clear: meta.del!.clear, delseq: meta.del!.delseq)
        }
        if meta.tags != nil {
            routeMetaTags(tags: meta.tags!)
        }
        // update listener
        listener?.onMeta(meta: meta)
    }

    /// Delete topic
    @discardableResult
    public func delete(hard: Bool) -> PromisedReply<ServerMessage> {
        // Delete works even if the topic is not attached.
        return tinode!.delTopic(topicName: name, hard: hard).then(
            onSuccess: { msg in
                self.topicLeft(unsub: true, code: msg?.ctrl?.code, reason: msg?.ctrl?.text)
                self.tinode!.stopTrackingTopic(topicName: self.name)
                self.persist(false)
                return nil
            }
        )
    }

    @discardableResult
    private func note(what: NoteType, fromMe: Bool = true, explicitSeq: Int? = nil) -> Int {
        var result = 0
        switch what {
        case .kRecv:
            let seq = description!.getSeq
            if description!.getRecv < seq {
                if !fromMe {
                    tinode!.noteRecv(topic: name, seq: seq)
                }
                result = seq
                description!.recv = seq
            }
        case .kRead:
            let seq = description!.getSeq
            if explicitSeq != nil || description!.getRead < seq {
                if !fromMe {
                    tinode!.noteRead(topic: name, seq: explicitSeq ?? seq)
                }
                if let eseq = explicitSeq {
                    if description!.getRead < eseq {
                        result = eseq
                        description!.read = eseq
                    }
                } else {
                    result = seq
                    description!.read = seq
                }
            }
        case .kKeyPress:
            if lastKeyPress.addingTimeInterval(kIntervalBetweenKeyPresses) < Date() {
                lastKeyPress = Date()
                tinode!.noteKeyPress(topic: name)
            }
        }
        return result
    }

    @discardableResult
    public func noteRead(explicitSeq: Int? = nil) -> Int {
        let result = note(what: .kRead, fromMe: false, explicitSeq: explicitSeq)
        if result > 0 {
            store?.setRead(topic: self, read: result)
        }
        return result
    }

    @discardableResult
    public func noteRecv(fromMe: Bool) -> Int {
        let result = note(what: .kRecv, fromMe: fromMe)
        if result > 0 {
            store?.setRecv(topic: self, recv: result)
        }
        return result
    }

    public func noteKeyPress() {
        note(what: .kKeyPress)
    }
    private func setSeq(seq: Int) {
        if description!.getSeq < seq {
            description!.seq = seq
        }
    }
    private func setRecv(recv: Int) {
        if description!.getRecv < recv {
            description!.recv = recv
        }
    }
    private func setRead(read: Int) {
        if description!.getRead < read {
            description!.read = read
        }
    }
    public func routeData(data: MsgServerData) {
        setSeq(seq: data.getSeq)
        touched = data.ts
        if let s = store {
            if s.msgReceived(topic: self, sub: getSubscription(for: data.from), msg: data) > 0 {
                noteRecv(fromMe: tinode!.isMe(uid: data.from))
            }
        } else {
            noteRecv(fromMe: tinode!.isMe(uid: data.from))
        }
        listener?.onData(data: data)
    }

    @discardableResult
    public func getMeta(query: MsgGetMeta) -> PromisedReply<ServerMessage> {
        return tinode!.getMeta(topic: name, query: query)
    }

    public func setMeta(meta: MsgSetMeta<DP, DR>) -> PromisedReply<ServerMessage> {
        return tinode!.setMeta(for: self.name, meta: meta).thenApply({ msg in
            if let ctrl = msg?.ctrl, ctrl.code < ServerMessage.kStatusMultipleChoices {
                self.update(ctrl: ctrl, meta: meta)
            }
            return nil
        })
    }
    public func setDescription(desc: MetaSetDesc<DP, DR>) -> PromisedReply<ServerMessage> {
        return setMeta(meta: MsgSetMeta<DP, DR>(desc: desc, sub: nil, tags: nil, cred: nil))
    }
    public func setDescription(pub: DP?, priv: DR?) -> PromisedReply<ServerMessage> {
        return setDescription(desc: MetaSetDesc<DP, DR>(pub: pub, priv: priv))
    }
    public func updateDefacs(auth: String?, anon: String?) -> PromisedReply<ServerMessage> {
        let newdacs: Defacs
        if let olddacs = self.defacs {
            newdacs = Defacs(from: olddacs)
            newdacs.update(auth: auth, anon: anon)
        } else {
            newdacs = Defacs(auth: auth, anon: anon)
        }
        return setDescription(desc: MetaSetDesc<DP, DR>(da: newdacs))
    }

    public func updateAccessMode(ac: AccessChange?) -> Bool {
        if description!.acs == nil {
            description!.acs = Acs()
        }
        return description!.acs!.update(from: ac)
    }
    public func setSubscription(sub: MetaSetSub) -> PromisedReply<ServerMessage> {
        return setMeta(meta: MsgSetMeta(desc: nil, sub: sub, tags: nil, cred: nil))
    }

    public func updateMode(update: String) -> PromisedReply<ServerMessage> {
        return updateMode(uid: nil, update: update)
    }

    public func updateMode(uid: String?, update: String) -> PromisedReply<ServerMessage> {
        var uid = uid
        let sub = getSubscription(for: uid ?? tinode?.myUid)
        if uid == tinode?.myUid {
            uid = nil
        }
        let uidIsSelf = uid == nil || sub == nil
        if description!.acs == nil {
            description!.acs = Acs()
        }
        let mode = AcsHelper(ah: uidIsSelf ? description!.acs!.want : sub!.acs!.given)
        if mode.update(from: update) {
            return setSubscription(sub: MetaSetSub(user: uid, mode: mode.description))
        }
        return PromisedReply<ServerMessage>(value: ServerMessage())
    }

    public func updateMuted(muted: Bool) -> PromisedReply<ServerMessage> {
        return updateMode(uid: nil, update: muted ? "-P" : "+P")
    }
    @discardableResult
    public func invite(user uid: String, in mode: String?) -> PromisedReply<ServerMessage> {
        var sub = getSubscription(for: uid)
        if sub != nil {
            sub!.acs?.given = mode != nil ? AcsHelper(str: mode) : nil
        } else {
            let subUnwrapped = Subscription<SP, SR>()
            subUnwrapped.topic = self.name
            subUnwrapped.user = uid
            subUnwrapped.acs = Acs()
            subUnwrapped.acs!.given = mode != nil ? AcsHelper(str: mode) : nil
            _ = store?.subNew(topic: self, sub: subUnwrapped)
            let user: User<SP>? = tinode?.getUser(with: uid)
            subUnwrapped.pub = user?.pub
            addSubToCache(sub: subUnwrapped)
            sub = subUnwrapped
        }
        listener?.onMetaSub(sub: sub!)
        listener?.onSubsUpdated()
        // Check if topic is already synchronized. If not, don't send the request, it will fail anyway.
        if isNew {
            return PromisedReply<ServerMessage>(error: TopicError.notSynchronized)
        }
        let metaSetSub = MetaSetSub(user: uid, mode: mode)
        return setMeta(meta: MsgSetMeta(desc: nil, sub: metaSetSub, tags: nil, cred: nil))
            .thenApply { [weak self] msg in
                if let topic = self {
                    topic.store?.subUpdate(topic: topic, sub: sub!)
                    topic.listener?.onMetaSub(sub: sub!)
                    topic.listener?.onSubsUpdated()
                }
                return nil
            }
    }
    @discardableResult
    public func eject(user uid: String, ban: Bool) -> PromisedReply<ServerMessage> {
        guard let sub = getSubscription(for: uid) else {
            return PromisedReply(error:
                TinodeError.notSubscribed(
                    "Can't eject user from topic \(name)"))
        }
        if ban {
            return invite(user: uid, in: "N")
        }
        if isNew {
            store?.subDelete(topic: self, sub: sub)
            listener?.onSubsUpdated()
            return PromisedReply(error: TinodeError.notSynchronized)
        }
        return tinode!.delSubscription(topicName: name, user: uid).thenApply({ msg in
                self.store?.subDelete(topic: self, sub: sub)
                self.removeSubFromCache(sub: sub)
                self.listener?.onSubsUpdated()
                return nil
            })
    }
    public func routeInfo(info: MsgServerInfo) {
        if info.what != Tinode.kNoteKp {
            if let sub = getSubscription(for: info.from) {
                switch info.what {
                case Tinode.kNoteRecv:
                    sub.recv = info.seq
                    store?.msgRecvByRemote(sub: sub, recv: info.seq)
                case Tinode.kNoteRead:
                    sub.read = info.seq
                    if sub.getRecv < sub.getRead {
                        sub.recv = sub.read
                        store?.msgRecvByRemote(sub: sub, recv: info.seq)
                    }
                    store?.msgReadByRemote(sub: sub, read: info.seq)
                default:
                    break
                }
            }
        }
        listener?.onInfo(info: info)
    }

    public func routePres(pres: MsgServerPres) {
        let what = MsgServerPres.parseWhat(what: pres.what)
        switch what {
        case .kOn, .kOff:
            if let sub = getSubscription(for: pres.src) {
                sub.online = (.kOn == what)
            }
        case .kDel:
            routeMetaDel(clear: pres.clear!, delseq: pres.delseq!)
        case .kTerm:
            topicLeft(unsub: false, code: ServerMessage.kStatusInternalServerError, reason: "term")
        case .kAcs:
            if let sub = getSubscription(for: pres.src) {
                sub.updateAccessMode(ac: pres.dacs)
                if sub.user == tinode?.myUid {
                    if self.updateAccessMode(ac: pres.dacs) {
                        store?.topicUpdate(topic: self)
                    }
                }
                if !sub.acs!.isModeDefined {
                    if isP2PType {
                        leave()
                    }
                    sub.deleted = Date()
                    processSub(newsub: sub)
                }
            } else {
                let acs = Acs(from: nil as Acs?)
                acs.update(from: pres.dacs)
                if acs.isModeDefined {
                    getMeta(query: metaGetBuilder().withSub(user: pres.src).build())
                }
            }
        default:
            Tinode.log.error("pres message - unknown what: %@", String(describing: pres.what))
        }
        listener?.onPres(pres: pres)
    }
    public func topicLeft(unsub: Bool?, code: Int?, reason: String?) {
        if attached {
            attached = false
            listener?.onLeave(unsub: unsub, code: code, text: reason)
        }
    }
    @discardableResult
    public func leave(unsub: Bool? = false) -> PromisedReply<ServerMessage> {
        if attached {
            return tinode!.leave(topic: name, unsub: unsub)
                .thenApply({ [weak self] msg in
                        guard let s = self else {
                            throw TinodeError.invalidState("Topic.self not available in result handler")
                        }
                        s.topicLeft(unsub: unsub, code: msg?.ctrl?.code, reason: msg?.ctrl?.text)
                        if unsub ?? false {
                            s.tinode?.stopTrackingTopic(topicName: s.name)
                            s.persist(false)
                        }
                        return nil
                    })
        }
        if !(unsub ?? false) {
            return PromisedReply(value: ServerMessage())
        }
        if tinode!.isConnected {
            return PromisedReply(error:
                TinodeError.notSubscribed("Can't leave topic that I'm not subscribed to \(name)"))
        }
        return PromisedReply(
            error: TinodeError.notConnected("Leaving topic when Tinode is not connected."))
    }

    private func processDelivery(ctrl: MsgServerCtrl?, id: Int64) {
        guard let ctrl = ctrl else {
            return
        }
        guard let seq = ctrl.getIntParam(for: "seq"), seq > 0 else {
            return
        }
        setSeq(seq: seq)
        touched = ctrl.ts
        if id > 0, let s = store {
            if s.msgDelivered(topic: self, dbMessageId: id,
                              timestamp: ctrl.ts, seq: seq) {
                setRecv(recv: seq)
            }
        } else {
            setRecv(recv: seq)
        }
        setRead(read: seq)
        store?.setRead(topic: self, read: seq)
    }
    public func publish(content: Drafty, head: [String: JSONValue]?, msgId: Int64) -> PromisedReply<ServerMessage> {
        var headers = head
        if content.isPlain && headers?["mime"] != nil {
            headers?.removeValue(forKey: "mime")
        }
        return tinode!.publish(topic: name, head: headers, content: content).then(
            onSuccess: { [weak self] msg in
                self?.processDelivery(ctrl: msg?.ctrl, id: msgId)
                return nil
            }, onFailure: { [weak self] err in
                self?.store?.msgSyncing(topic: self!, dbMessageId: msgId, sync: false)
                // Rethrow exception to trigger the next possible failure listener.
                throw err
            })
    }
    public func publish(content: Drafty) -> PromisedReply<ServerMessage> {
        let head = !content.isPlain ? Tinode.draftyHeaders(for: content) : nil
        var id: Int64 = -1
        if let s = store {
            id = s.msgSend(topic: self, data: content, head: head)
        }
        if attached {
            return publish(content: content, head: head, msgId: id)
        } else {
            return subscribe()
                .thenApply({ [weak self] msg in
                    return self?.publish(content: content, head: head, msgId: id)
                }).thenCatch({ [weak self] err in
                    self?.store?.msgSyncing(topic: self!, dbMessageId: id, sync: false)
                    throw err
                })
        }
    }
    private func sendPendingDeletes(hard: Bool) -> PromisedReply<ServerMessage>? {
        if let pendingDeletes = self.store?.getQueuedMessageDeletes(topic: self, hard: hard), !pendingDeletes.isEmpty {
            return self.tinode!.delMessage(
                topicName: self.name, ranges: pendingDeletes, hard: hard)
                .thenApply({ [weak self] msg in
                        if let id = msg?.ctrl?.getIntParam(for: "del"), let s = self {
                            s.clear = id
                            s.maxDel = id
                            _ = s.store?.msgDelete(topic: s, delete: id, deleteAllIn: pendingDeletes)
                        }
                        return nil
                    })
        }
        return nil
    }

    private func delMessages(from fromId: Int, to toId: Int, hard: Bool) -> PromisedReply<ServerMessage> {
        store?.msgMarkToDelete(topic: self, from: fromId, to: toId, markAsHard: hard)
        if attached {
            return tinode!.delMessage(topicName: self.name, fromId: fromId, toId: toId, hard: hard).then(
                onSuccess: { [weak self] msg in
                    if let s = self, let delId = msg?.ctrl?.getIntParam(for: "del"), delId > 0 {
                        s.clear = delId
                        s.maxDel = delId
                        s.store?.msgDelete(topic: s, delete: delId, deleteFrom: fromId, deleteTo: toId)
                    }
                    return nil
                })
        }
        if tinode?.isConnected ?? false {
            return PromisedReply<ServerMessage>(error: TinodeError.notSubscribed("Not subscribed to topic."))
        }
        return PromisedReply<ServerMessage>(error: TinodeError.notConnected("Tinode not connected."))
    }

    public func delMessages(hard: Bool) -> PromisedReply<ServerMessage> {
        return delMessages(from: 0, to: (self.seq ?? 0) + 1, hard: hard)
    }

    public func delMessage(id: Int, hard: Bool)  -> PromisedReply<ServerMessage> {
        return delMessages(from: id, to: id + 1, hard: hard)
    }

    public func syncOne(msgId: Int64) -> PromisedReply<ServerMessage> {
        guard let m = store?.getMessageById(topic: self, dbMessageId: msgId) else {
            return PromisedReply<ServerMessage>(value: ServerMessage())
        }
        if m.isDeleted {
            return tinode!.delMessage(topicName: name, msgId: m.seqId, hard: m.isDeleted(hard: true))
        }
        if m.isReady, let content = m.content {
            store?.msgSyncing(topic: self, dbMessageId: msgId, sync: true)
            return self.publish(content: content, head: m.head, msgId: msgId)
        }
        return PromisedReply<ServerMessage>(value: ServerMessage())
    }
    public func syncAll() -> PromisedReply<ServerMessage> {
        var result: PromisedReply<ServerMessage> = PromisedReply<ServerMessage>(value: ServerMessage())
        // Soft deletes.
        if let r = self.sendPendingDeletes(hard: false) {
            result = r
        }
        // Hard deletes.
        if let r = self.sendPendingDeletes(hard: true) {
            result = r
        }

        // Pending messages.
        guard let pendingMsgs = self.store?.getQueuedMessages(topic: self) else {
            return result
        }
        for msg in pendingMsgs {
            let msgId = msg.msgId
            _ = self.store?.msgSyncing(topic: self, dbMessageId: msgId, sync: true)
            result = self.publish(content: msg.content!, head: msg.head, msgId: msgId)
        }
        return result
    }

    public func setSetAndFetch(newSeq: Int?) {
        guard let newSeq = newSeq, newSeq > description!.getSeq else { return }
        let limit = newSeq - description!.getSeq
        self.setSeq(seq: newSeq)
        if !self.attached {
            self.subscribe(set: nil, get: self.metaGetBuilder().withLaterData(limit: limit).build()).thenApply({ msg in
                self.leave()
                return nil
            })
        }
    }
}
