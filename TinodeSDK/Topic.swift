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
    var cachedMessageRange: Storage.Range? { get }
    var isArchived: Bool { get }
    var isJoiner: Bool { get }
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
        // Called by MeTopic when topic descriptor as contact is updated.
        open func onContUpdate(sub: Subscription<SP, SR>) {}
    }

    public class MetaGetBuilder {
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
            if let r = topic.cachedMessageRange {
                return withData(since: nil, before: r.min > 0 ? r.min : nil, limit: limit)
            }
            return withData(since: nil, before: nil, limit: limit)
        }
        public func withLaterData(limit: Int?) -> MetaGetBuilder {
            if let r = topic.cachedMessageRange {
                return withData(since: r.max > 0 ? r.max + 1 : nil, before: nil, limit: limit)
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
        public func withCred() -> MetaGetBuilder {
            meta.setCred()
            return self
        }
        public func build() -> MsgGetMeta {
            return meta
        }
    }

    fileprivate weak var tinode: Tinode? = nil
    public var name: String = ""
    public var isNew: Bool {
        get { return Topic.isNewByName(name: name)}
    }

    public var updated: Date? {
        get {
            return description?.updated
        }
        set {
            description?.updated = newValue
        }
    }

    public var touched: Date? {
        get {
            return description?.touched
        }
        set {
            description?.touched = newValue
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
        get {
            let unread = (description?.seq ?? 0) - (description?.read ?? 0)
            return unread > 0 ? unread : 0
        }
    }

    public var subsLastUpdated: Date? = nil
    public var subsUpdated: Date? {
        get { return subsLastUpdated }
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
    fileprivate var subs: [String:Subscription<SP,SR>]? = nil
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
    public var isDeleter: Bool {
        return description?.acs?.isDeleter ?? false
    }
    public var isArchived: Bool {
        return false
    }

    // Storage is owned by Tinode.
    weak public var store: Storage? = nil
    public var payload: Payload? = nil
    public var isPersisted: Bool { get { return payload != nil } }

    public var cachedMessageRange: Storage.Range? {
        get {
            return store?.getCachedMessagesRange(topic: self)
        }
    }

    // Tells how many topic subscribers have reported the message as read or received.
    internal func msgReadRecvCount(seq: Int?, read: Bool) -> Int {
        if subs == nil {
            loadSubs()
        }

        guard let subs = subs, let me = tinode?.myUid, let seq = seq, seq > 0 else { return 0 }
        return  subs.reduce(0, { (count, tuple) -> Int in
            let (key, sub) = tuple
            if key != me && ((read ? sub.read : sub.recv) ?? Int.max) >= seq {
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
        return name.starts(with: Tinode.kTopicNew)
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

    public func getMetaGetBuilder() -> MetaGetBuilder {
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
    public func subscribe() -> PromisedReply<ServerMessage>? {
        var setMsg: MsgSetMeta<DP, DR>? = nil
        var getMsg: MsgGetMeta? = nil
        if isNew {
            setMsg = MsgSetMeta<DP, DR>(
                desc: MetaSetDesc(pub: self.pub, priv: self.priv),
                sub: nil,
                tags: self.tags, cred: nil)
        } else {
            getMsg = getMetaGetBuilder()
                .withDesc().withData().withSub().withTags().build()
        }
        return subscribe(set: setMsg, get: getMsg)
    }
    @discardableResult
    public func subscribe(set: MsgSetMeta<DP, DR>?, get: MsgGetMeta?) -> PromisedReply<ServerMessage>? {
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
        persist(true)
        let tnd = tinode!
        guard tnd.isConnected else {
            return PromisedReply(error: TinodeError.notConnected("Cannot subscribe to topic. No server connection."))
        }
        guard tnd.isConnectionAuthenticated else {
            return PromisedReply(error: TinodeError.invalidState("Connection is not authenticated.") )
        }
        return try! tnd.subscribe(to: name, set: set, get: get)?.then(
            onSuccess: { [weak self] msg in
                let isAttached = self?.attached ?? false
                if !isAttached {
                    self?.attached = true
                    if let ctrl = msg?.ctrl {
                        if !(ctrl.params?.isEmpty ?? false) {
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
                    if code >= 400 && code < 500 {
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

    fileprivate func update(sub: Subscription<SP, SR>) {
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
    fileprivate func update(desc: Description<DP, DR>) {
        if description?.merge(desc: desc) ?? false {
            store?.topicUpdate(topic: self)
        }
    }
    fileprivate func update(tags: [String]) {
        self.tags = tags
        store?.topicUpdate(topic: self)
    }
    fileprivate func update(desc: MetaSetDesc<DP, DR>) {
        if self.description?.merge(desc: desc) ?? false {
            self.store?.topicUpdate(topic: self)
        }
    }
    // Topic sent an update to description or subscription, got a confirmation, now
    // update local data with the new info.
    fileprivate func update(ctrl: MsgServerCtrl, meta: MsgSetMeta<DP, DR>) {
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
    fileprivate func update(acsMap: [String:String]?, sub: MetaSetSub) {
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
    fileprivate func addSubToCache(sub: Subscription<SP, SR>) {
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
            sub = getSubscription(for: newsub.user)
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
    private func routeMetaDel(clear: Int, delseq: [MsgDelRange]) {
        if let s = store {
            for range in delseq {
                let lo = range.low ?? 0
                s.msgDelete(topic: self, delete: clear, deleteFrom: lo, deleteTo: range.hi ?? lo + 1)
            }
        }
        self.maxDel = clear
        listener?.onData(data: nil)
    }

    fileprivate func routeMetaSub(meta: MsgServerMeta) {
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
    public func delete() -> PromisedReply<ServerMessage>? {
        // Delete works even if the topic is not attached.
        return try! tinode!.delTopic(topicName: name)?.then(
            onSuccess: { msg in
                self.topicLeft(unsub: true, code: msg?.ctrl?.code, reason: msg?.ctrl?.text)
                self.tinode!.stopTrackingTopic(topicName: self.name)
                self.persist(false)
                return nil
            }
        )
    }

    @discardableResult
    private func note(what: NoteType) -> Int {
        var result = 0
        switch what {
        case .kRecv:
            let seq = description!.getSeq
            if description!.getRecv < seq {
                tinode!.noteRecv(topic: name, seq: seq)
                result = seq
                description!.recv = seq
            }
        case .kRead:
            let seq = description!.getSeq
            if description!.getRead < seq {
                tinode!.noteRead(topic: name, seq: seq)
                result = seq
                description!.read = seq
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
    public func noteRead() -> Int {
        let result = note(what: .kRead)
        store?.setRead(topic: self, read: result)
        return result
    }

    @discardableResult
    public func noteRecv() -> Int {
        let result = note(what: .kRecv)
        store?.setRecv(topic: self, recv: result)
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
        if let s = store {
            if s.msgReceived(topic: self, sub: getSubscription(for: data.from), msg: data) > 0 {
                noteRecv()
            }
        } else {
            noteRecv()
        }
        setSeq(seq: data.getSeq)
        listener?.onData(data: data)
    }

    @discardableResult
    public func getMeta(query: MsgGetMeta) -> PromisedReply<ServerMessage>? {
        return tinode?.getMeta(topic: name, query: query)
    }

    public func setMeta(meta: MsgSetMeta<DP, DR>) -> PromisedReply<ServerMessage>? {
        do {
            return try tinode?.setMeta(for: self.name, meta: meta)?.thenApply(
                onSuccess: { msg in
                    if let ctrl = msg?.ctrl, ctrl.code < 300 {
                        self.update(ctrl: ctrl, meta: meta)
                    }
                    return nil
                })
        } catch {
            return nil
        }
    }
    public func setDescription(desc: MetaSetDesc<DP, DR>) -> PromisedReply<ServerMessage>? {
        return setMeta(meta: MsgSetMeta<DP, DR>(desc: desc, sub: nil, tags: nil, cred: nil))
    }
    public func setDescription(pub: DP?, priv: DR?) -> PromisedReply<ServerMessage>? {
        return setDescription(desc: MetaSetDesc<DP, DR>(pub: pub, priv: priv))
    }
    public func updateDefacs(auth: String?, anon: String?) -> PromisedReply<ServerMessage>? {
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
            description!.acs = Acs(from: nil as Acs?)
        }
        return description!.acs!.update(from: ac)
    }
    public func setSubscription(sub: MetaSetSub) -> PromisedReply<ServerMessage>? {
        return setMeta(meta: MsgSetMeta(desc: nil, sub: sub, tags: nil, cred: nil))
    }
    public func updateMode(uid: String?, update: String) -> PromisedReply<ServerMessage>? {
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
    public func updateMuted(muted: Bool) -> PromisedReply<ServerMessage>? {
        return updateMode(uid: nil, update: muted ? "-P" : "+P")
    }
    @discardableResult
    public func invite(user uid: String, in mode: String?) -> PromisedReply<ServerMessage>? {
        var sub = getSubscription(for: uid)
        if sub != nil {// : Subscription<SP, SR>
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
        do {
            let metaSetSub = MetaSetSub(user: uid, mode: mode)
            //metaSetSub.user = uid
            //metaSetSub.mode = mode
            let future = setMeta(meta: MsgSetMeta(desc: nil, sub: metaSetSub, tags: nil, cred: nil))
            return try future?.thenApply(
                onSuccess: { [weak self] msg in
                    if let topic = self {
                        topic.store?.subUpdate(topic: topic, sub: sub!)
                        topic.listener?.onMetaSub(sub: sub!)
                        topic.listener?.onSubsUpdated()
                    }
                    return nil
                })
        } catch {
            return PromisedReply<ServerMessage>(
                error: TopicError.subscriptionFailure(
                    error.localizedDescription))
        }
    }
    @discardableResult
    public func eject(user uid: String, ban: Bool) -> PromisedReply<ServerMessage>? {
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
        do {
            return try tinode!.delSubscription(topicName: name, user: uid)?.then(
                onSuccess: { msg in
                    self.store?.subDelete(topic: self, sub: sub)
                    self.removeSubFromCache(sub: sub)
                    self.listener?.onSubsUpdated()
                    return nil
                },
                onFailure: nil)
        } catch { return nil }
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
            topicLeft(unsub: false, code: 500, reason: "term")
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
                    getMeta(query: getMetaGetBuilder().withSub(user: pres.src).build())
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
    public func leave(unsub: Bool? = false) -> PromisedReply<ServerMessage>? {
        if attached {
            return try! tinode?.leave(topic: name, unsub: unsub)?
                .thenApply(
                    onSuccess: { [weak self] msg in
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
        if tinode?.isConnected ?? false {
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
    public func publish(content: Drafty, msgId: Int64) -> PromisedReply<ServerMessage>? {
        return try! tinode!.publish(topic: name, data: content)?.then(
            onSuccess: { [weak self] msg in
                self?.processDelivery(ctrl: msg?.ctrl, id: msgId)
                return nil
            }, onFailure: { [weak self] err in
                self?.store?.msgSyncing(topic: self!, dbMessageId: msgId, sync: false)
                // Rethrow exception to trigger the next possible failure listener.
                throw err
            })
    }
    public func publish(content: Drafty) -> PromisedReply<ServerMessage>? {
        var id: Int64 = -1
        if let s = store {
            id = s.msgSend(topic: self, data: content)
        }
        if attached {
            return publish(content: content, msgId: id)
        } else {
            return try! subscribe()?.thenApply(
                onSuccess: { [weak self] msg in
                    return self?.publish(content: content, msgId: id)
                })?.thenCatch(onFailure: { [weak self] err in
                    self?.store?.msgSyncing(topic: self!, dbMessageId: id, sync: false)
                    throw err
                })
        }
    }
    private func sendPendingDeletes(hard: Bool) -> PromisedReply<ServerMessage>? {
        if let pendingDeletes = self.store?.getQueuedMessageDeletes(topic: self, hard: hard), !pendingDeletes.isEmpty {
            return try! self.tinode?.delMessage(
                topicName: self.name, list: pendingDeletes, hard: hard)?.then(
                    onSuccess: { [weak self] msg in
                        if let id = msg?.ctrl?.getIntParam(for: "del"), let s = self {
                            _ = s.store?.msgDelete(topic: s, delete: id, deleteAll: pendingDeletes)
                        }
                        return nil
                    }, onFailure: nil)
        }
        return nil
    }

    private func delMessages(from fromId: Int, to toId: Int, hard: Bool) -> PromisedReply<ServerMessage>? {
        store?.msgMarkToDelete(topic: self, from: fromId, to: toId, markAsHard: hard)
        if attached {
            do {
                return try tinode?.delMessage(topicName: self.name, fromId: fromId, toId: toId, hard: hard)?.then(
                    onSuccess: { [weak self] msg in
                        if let delId = msg?.ctrl?.getIntParam(for: "del"), delId > 0 {
                            self?.store?.msgDelete(topic: self!, delete: delId, deleteFrom: fromId, deleteTo: toId)
                        }
                        return nil
                    })
            } catch {
                return PromisedReply<ServerMessage>(error: error)
            }
        }
        if tinode?.isConnected ?? false {
            return PromisedReply<ServerMessage>(error: TinodeError.notSubscribed("Not subscribed to topic."))
        }
        return PromisedReply<ServerMessage>(error: TinodeError.notConnected("Tinode not connected."))
    }

    public func delMessages(hard: Bool) -> PromisedReply<ServerMessage>? {
        return delMessages(from: 0, to: (self.seq ?? 0) + 1, hard: hard)
    }

    public func delMessage(id: Int, hard: Bool)  -> PromisedReply<ServerMessage>? {
        return delMessages(from: id, to: 0, hard: hard)
    }

    public func syncOne(msgId: Int64) -> PromisedReply<ServerMessage>? {
        guard let m = store?.getMessageById(topic: self, dbMessageId: msgId) else {
            return PromisedReply<ServerMessage>(value: ServerMessage())
        }
        if m.isDeleted {
            return tinode?.delMessage(topicName: name, msgId: m.seqId, hard: m.isDeleted(hard: true))
        }
        if m.isReady, let content = m.content {
            store?.msgSyncing(topic: self, dbMessageId: msgId, sync: true)
            return self.publish(content: content, msgId: msgId)
        }
        return nil
    }
    public func syncAll() -> PromisedReply<ServerMessage>? {
        var result: PromisedReply<ServerMessage>? = PromisedReply<ServerMessage>(value: ServerMessage())
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
            result = self.publish(content: msg.content!, msgId: msgId)
        }
        return result
    }
}

open class MeTopic<DP: Codable & Mergeable>: Topic<DP, PrivateType, DP, PrivateType> {
    public init(tinode: Tinode?, l: MeTopic<DP>.Listener?) {
        super.init(tinode: tinode, name: Tinode.kTopicMe, l: l)
    }
    public init(tinode: Tinode?, desc: Description<DP, PrivateType>) {
        super.init(tinode: tinode, name: Tinode.kTopicMe, desc: desc)
    }

    override public var subsUpdated: Date? {
        get { return tinode?.topicsUpdated }
    }

    override func loadSubs() -> Int {
        // Don't attempt to load subscriptions: 'me' subscriptions are stored as topics.
        return 0
    }
    override public func topicLeft(unsub: Bool?, code: Int?, reason: String?) {
        super.topicLeft(unsub: unsub, code: code, reason: reason)
        if let topics = tinode?.getTopics() {
            for t in topics {
                t.online = false
            }
        }
    }
    override public func routePres(pres: MsgServerPres) {
        let what = MsgServerPres.parseWhat(what: pres.what)
        if what == .kTerm {
            // The 'me' topic itself is detached. Mark as unsubscribed.
            super.routePres(pres: pres)
            return
        }
        // "what":"tags" has src == nil
        if let topic = pres.src != nil ? tinode!.getTopic(topicName: pres.src!) : nil {
            switch what {
            case .kOn: // topic came online
                topic.online = true
            case .kOff: // topic went offline
                topic.online = false
                topic.lastSeen = LastSeen(when: Date(), ua: nil)
            case .kMsg: // new message received
                topic.seq = pres.seq
                topic.touched = Date()
            case .kUpd: // pub/priv updated
                getMeta(query: getMetaGetBuilder().withSub(user: pres.src).build())
            case .kAcs: // access mode changed
                if topic.updateAccessMode(ac: pres.dacs) {
                    self.store?.topicUpdate(topic: topic)
                }
            case .kUa: // user agent changed
                topic.lastSeen = LastSeen(when: Date(), ua: pres.ua)
            case .kRecv: // user's other session marked some messages as received
                if (topic.recv ?? -1) < (pres.seq ?? -1) {
                    topic.recv = pres.seq
                    self.store?.setRecv(topic: topic, recv: pres.seq!)
                }
            case .kRead: // user's other session marked some messages as read
                if (topic.read ?? -1) < (pres.seq ?? -1) {
                    topic.read = pres.seq
                    self.store?.setRead(topic: topic, read: topic.read!)
                    if (topic.recv ?? -1) < (topic.read ?? -1) {
                        topic.recv = topic.read
                        self.store?.setRecv(topic: topic, recv: topic.read!)
                    }
                }
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
            // New topic
            switch what {
            case .kAcs:
                let acs = Acs()
                acs.update(from: pres.dacs)
                if acs.isModeDefined {
                    getMeta(query: getMetaGetBuilder().withSub(user: pres.src).build())
                } else {
                    Tinode.log.error("ME.acs - unexpected access mode: %@", String(describing: pres.dacs))
                }
            case .kTags:
                // Account tags updated
                getMeta(query: getMetaGetBuilder().withTags().build())
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

    override fileprivate func routeMetaSub(meta: MsgServerMeta) {
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
                        } /*else if let t = topic as? DefaultFndTopic {
                            t.update(sub: sub)
                        } */
                        else {
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
}
public class FndTopic<SP: Codable>: Topic<String, String, SP, Array<String>> {
    init(tinode: Tinode?) {
        super.init(tinode: tinode, name: Tinode.kTopicFnd)
    }

    @discardableResult
    override public func setMeta(meta: MsgSetMeta<String, String>) -> PromisedReply<ServerMessage>? {
        if self.subs != nil {
            self.subs!.removeAll()
            self.subs = nil
            self.subsLastUpdated = nil
            self.listener?.onSubsUpdated()
        }
        return super.setMeta(meta: meta)
    }

    override func routeMetaSub(meta: MsgServerMeta) {
        if let subscriptions = meta.sub {
            for upd in subscriptions {
                var sub = getSubscription(for: upd.uniqueId)
                if sub != nil {
                    _ = sub!.merge(sub: upd as! Subscription<SP, [String]>)
                } else {
                    sub = upd as? Subscription<SP, [String]>
                    self.addSubToCache(sub: sub!)
                }
                self.listener?.onMetaSub(sub: sub!)
            }
        }
        self.listener?.onSubsUpdated()
    }

    override public func getSubscriptions() -> [Subscription<SP, Array<String>>]? {
        guard let v = subs?.values else { return nil }
        return Array(v)
    }

    override func addSubToCache(sub: Subscription<SP, [String]>) {
        guard let unique = sub.user ?? sub.topic else { return }

        if subs == nil {
            subs = [:]
        }
        subs![unique] = sub
    }
}

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
    public convenience init(in tinode: Tinode?, forwardingEventsTo l: Listener? = nil) {
        self.init(tinode: tinode!, name: Tinode.kTopicNew + tinode!.nextUniqueString(), l: l)
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
