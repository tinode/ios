//
//  Topic.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

protocol Payload: class {
    
}
protocol TopicProto: class {
    var name: String { get }
    var updated: Date? { get set }
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
    var cachedMessageRange: Storage.Range? { get }

    func serializePub() -> String?
    func serializePriv() -> String?
    @discardableResult
    func deserializePub(from data: String?) -> Bool
    @discardableResult
    func deserializePriv(from data: String?) -> Bool

    func allMessagesReceived(count: Int?)
    func routeMeta(meta: MsgServerMeta)
    func routeData(data: MsgServerData)
    func routePres(pres: MsgServerPres)
    func routeInfo(info: MsgServerInfo)
    //func setStorage(store: Storage?)
}

enum TopicType: Int {
    case me = 0x01
    case fnd = 0x02
    case grp = 0x04
    case p2p = 0x08
    case user = 0x0c // .grp | .p2p
    case system = 0x03 // .m2 | .fnd
    case unknown = 0x00
    case any = 0x0f // .user | .system
}

class Topic<DP: Codable, DR: Codable, SP: Codable, SR: Codable>: TopicProto {
    enum TopicError: Error {
        case alreadySubscribed
    }

    enum NoteType {
        case kRead
        case kRecv
    }
    
    public class Listener {
        
        func onSubscribe(code: Int, text: String) {}
        func onLeave(unsub: Bool?, code: Int?, text: String?) {}

        // Process {data} message.
        func onData(data: MsgServerData?) {}
        // All requested data messages received.
        func onAllMessagesReceived(count: Int) {}
        
        // {info} message received.
        func onInfo(info: MsgServerInfo) {}
        // {meta} message received.
        func onMeta(meta: MsgServerMeta) {}
        // {meta what="sub"} message received, and this is one of the subs.
        func onMetaSub(sub: Subscription<SP, SR>) {}
        // {meta what="desc"} message received.
        func onMetaDesc(desc: Description<DP, DR>) {}
        // {meta what="tags"} message received.
        func onMetaTags(tags: [String]) {}
        // {meta what="sub"} message received and all subs were processed.
        func onSubsUpdated() {}
        // {pres} received.
        func onPres(pres: MsgServerPres) {}
        // {pres what="on|off"} is received.
        func onOnline(online: Bool) {}
        // Called by MeTopic when topic descriptor as contact is updated.
        func onContUpdate(sub: Subscription<SP, SR>) {}
    }
    
    class MetaGetBuilder {
        let topic: TopicProto
        var meta: MsgGetMeta
        
        init(parent: TopicProto) {
            self.topic = parent
            self.meta = MsgGetMeta()
        }
        
        func withGetData(since: Int?, before: Int?, limit: Int?) -> MetaGetBuilder {
            meta.setData(since: since, before: before, limit: limit)
            return self
        }
        func withGetLaterData(limit: Int?) -> MetaGetBuilder {
            if let r = topic.cachedMessageRange {
                return withGetData(since: r.max > 0 ? r.max + 1 : nil, before: nil, limit: limit)
            }
            return withGetData(since: nil, before: nil, limit: limit)
        }
        func withGetData() -> MetaGetBuilder {
            return withGetLaterData(limit: nil)
        }

        func withGetDel(since: Int?, limit: Int?) -> MetaGetBuilder {
            meta.setDel(since: since, limit: limit)
            return self
        }
        func withGetLaterDel(limit: Int?) -> MetaGetBuilder {
            return withGetDel(since: topic.maxDel + 1, limit: limit);
        }
        func withGetDel() -> MetaGetBuilder {
            return withGetLaterDel(limit: nil)
        }

        func withGetDesc() -> MetaGetBuilder {
            return withGetDesc(ims: topic.updated)
        }
        func withGetDesc(ims: Date?) -> MetaGetBuilder {
            meta.setDesc(ims: ims)
            return self
        }
        func withGetSub(user: String?, ims: Date?, limit: Int?) -> MetaGetBuilder {
            meta.setSub(user: user, ims: ims, limit: limit)
            return self
        }
        func withGetSub(user: String?) -> MetaGetBuilder {
            return withGetSub(user: user, ims: topic.subsUpdated, limit: nil)
        }

        func withGetSub(ims: Date?, limit: Int?) -> MetaGetBuilder {
            return withGetSub(user: nil, ims: ims, limit: limit)
        }
        func withGetSub() -> MetaGetBuilder {
            return withGetSub(user: nil, ims: topic.subsUpdated, limit: nil)
        }
        func withGetTags() -> MetaGetBuilder {
            meta.setTags()
            return self
        }
        func build() -> MsgGetMeta {
            return meta
        }
    }
    
    fileprivate weak var tinode: Tinode? = nil
    var name: String = ""
    var isNew: Bool {
        get { return Topic.isNewByName(name: name)}
    }
    
    var updated: Date? {
        get {
            return description?.updated
        }
        set {
            description?.updated = newValue
        }
    }
    var read: Int? {
        get {
            return description?.read
        }
        set {
            if (newValue ?? -1) > (description?.read ?? -1) {
                description?.read = newValue
            }
        }
    }
    var recv: Int? {
        get {
            return description?.recv
        }
        set {
            if (newValue ?? -1) > (description?.recv ?? -1) {
                description?.recv = newValue
            }
        }
    }
    var seq: Int? {
        get {
            return description?.seq
        }
        set {
            if (newValue ?? -1) > (description?.seq ?? -1) {
                description?.seq = newValue
            }
        }
    }
    var clear: Int? {
        get {
            return description?.clear
        }
        set {
            if (newValue ?? -1) > (description?.clear ?? -1) {
                description?.clear = newValue
            }
        }
    }
    var subsLastUpdated: Date? = nil
    var subsUpdated: Date? {
        get { return subsLastUpdated }
    }
    var accessMode: Acs? {
        get { return description?.acs }
        set { description?.acs = newValue }
    }
    var defacs: Defacs? {
        get { return description?.defacs }
        set { description?.defacs = defacs }
    }
    
    // The bulk of topic data
    private var description: Description<DP, DR>? = nil
    var pub: DP? {
        get { return description?.pub }
    }
    var priv: DR? {
        get { return description?.priv }
    }
    var attached = false
    weak var listener: Listener? = nil
    // Cache of topic subscribers indexed by userID
    private var subs: [String:Subscription<SP,SR>]? = nil
    var tags: [String]? = nil
    private var lastKeyPress: Int64 = 0
    private var online: Bool = false {
        didSet {
            if oldValue != online {
                listener?.onOnline(online: online)
            }
        }
    }
    private var lastSeen: LastSeen? = nil
    var maxDel: Int = 0 {
        didSet {
            if maxDel < oldValue {
                maxDel = oldValue
            }
        }
    }
    
    var topicType: TopicType {
        get {
            return Topic.topicTypeByName(name: self.name)
        }
    }
    var isP2PType: Bool {
        get {
            return topicType == TopicType.p2p
        }
    }
    // Storage is owned by Tinode.
    weak var store: Storage? = nil
    var payload: Payload? = nil
    var isPersisted: Bool { get { return payload != nil } }
    var cachedMessageRange: Storage.Range? {
        get {
            return store?.getCachedMessagesRange(topic: self)
        }
    }
    
    init() {}

    static func topicTypeByName(name: String?) -> TopicType {
        var r: TopicType = .unknown
        if let name = name, !name.isEmpty {
            switch name {
            case Tinode.kTopicMe:
                r = .me
            case Tinode.kTopicFnd:
                r = .fnd
                break
            default:
                if name.starts(with: Tinode.kTopicGrpPrefix) || name.starts(with: Tinode.kTopicNew) {
                    r = .grp
                } else if name.starts(with: Tinode.kTopicUsrPrefix) {
                    r = .p2p
                }
                break
            }
        }
        return r
    }
    init(tinode: Tinode?, name: String, l: Listener? = nil) throws {
        guard tinode != nil else {
            throw TinodeError.invalidState("Tinode cannot be nil")
        }
        self.tinode = tinode
        self.name = name
        self.description = Description()
        self.listener = l
    }
    convenience init(tinode: Tinode?) throws {
        guard tinode != nil else {
            throw TinodeError.invalidState("Tinode cannot be nil")
        }
        try self.init(tinode: tinode!, name: Tinode.kTopicNew + tinode!.nextUniqueString())
    }
    init(tinode: Tinode?, sub: Subscription<SP, SR>) throws {
        guard tinode != nil else {
            throw TinodeError.invalidState("Tinode cannot be nil")
        }
        self.tinode = tinode
        self.name = sub.topic!
        self.description = Description()
        _ = self.description!.merge(sub: sub)

        if sub.online != nil {
            self.online = sub.online!
        }
    }
    init(tinode: Tinode?, name: String, desc: Description<DP, DR>) throws {
        guard tinode != nil else {
            throw TinodeError.invalidState("Tinode cannot be nil")
        }
        self.tinode = tinode
        self.name = name
        self.description = Description()
        _ = self.description!.merge(desc: desc)
    }
    
    public static func isNewByName(name: String) -> Bool {
        return name.starts(with: Tinode.kTopicNew)
    }
    private func setUpdated(updated: Date) {
        description?.updated = updated
    }
    private func setName(name: String) {
        self.name = name
    }
    /*
    private func serializeObject<T: Codable>(t: T) -> String? {
        guard let jsonData = try? Tinode.jsonEncoder.encode(t) else {
            return nil
        }
        let typeName = String(describing: T.self)
        let json = String(decoding: jsonData, as: UTF8.self)
        return [typeName, json].joined(separator: ";")
    }
    */
    public func serializePub() -> String? {
        guard let p = pub else { return nil }
        return Tinode.serializeObject(t: p)
    }
    public func serializePriv() -> String? {
        guard let p = priv else { return nil }
        return Tinode.serializeObject(t: p)
    }
    /*
    private func deserializeObject<T: Codable>(from data: String?) -> T? {
        guard let parts = data?.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true), parts.count == 2 else {
            return nil
        }
        guard parts[0] == String(describing: T.self), let d = String(parts[1]).data(using: .utf8) else {
            return nil
        }
        return try? Tinode.jsonDecoder.decode(T.self, from: d)
    }
    */
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

    func getMetaGetBuilder() -> MetaGetBuilder {
        return MetaGetBuilder(parent: self)
    }

    @discardableResult
    func subscribe() throws -> PromisedReply<ServerMessage> {
        var setMsg: MsgSetMeta<DP, DR>? = nil
        if let d = description, isNew && (d.pub != nil || d.priv != nil) {
            setMsg = MsgSetMeta<DP, DR>(desc: MetaSetDesc(pub: d.pub, priv: d.priv), sub: nil, tags: nil)
        }
        let getMsg = getMetaGetBuilder().withGetDesc().withGetData().withGetSub().withGetTags().build()
        return try subscribe(set: setMsg, get: getMsg)
    }
    @discardableResult
    func subscribe(set: MsgSetMeta<DP, DR>?, get: MsgGetMeta?) throws -> PromisedReply<ServerMessage> {
        if attached {
            throw TopicError.alreadySubscribed
        }
        let name = self.name
        var newTopic = false
        if tinode!.getTopic(topicName: name) == nil {
            tinode!.registerTopic(topic: self)
            newTopic = true
        }
        if !tinode!.isConnected {
            throw TinodeError.notConnected("Cannot subscribe to topic. No server connection.")
        }
        return try tinode!.subscribe(to: name, set: set, get: get).then(
            onSuccess: { [weak self] msg in
                let isAttached = self?.attached ?? false
                if !isAttached {
                    self?.attached = true
                    if let ctrl = msg.ctrl {
                        if !(ctrl.params?.isEmpty ?? false) {
                            self?.description?.acs = Acs(from: ctrl.getStringDict(for: "acs"))
                            //print("acsStr: \(String(describing: acsStr))")
                            if self?.isNew ?? false {
                                self?.setUpdated(updated: ctrl.ts)
                                self?.setName(name: ctrl.topic!)
                                _ = self?.tinode?.changeTopicName(topic: self!, oldName: name)
                                // set updated
                                // set name
                                // tinode change topic name
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
                if let e = err as? TinodeError, newTopic {
                    if case TinodeError.serverResponseError(let code, _, _) = e {
                        if code >= 400 && code < 500 {
                            self?.tinode?.unregisterTopic(topicName: name)
                        }
                    }
                }
                // To next handler.
                throw err
            })!
    }

    func allMessagesReceived(count: Int?) {
        print("allMessagesReceived --> \(String(describing: count))")
        listener?.onAllMessagesReceived(count: count ?? 0)
    }

    private func loadSubs() -> Int {
        // todo: implement
        return 0
    }
    func getSubscription(for key: String?) -> Subscription<SP, SR>? {
        if subs == nil {
            _ = loadSubs()
        }
        if let k = key {
            return subs != nil ? subs![k] : nil
        } else {
            return nil
        }
    }
    private func routeMetaDesc(meta: MsgServerMeta) {
        print("routing desc")
        update(desc: meta.desc as! Description<DP, DR>)
        if case .p2p = topicType {
            print("updating user")
            tinode?.updateUser(uid: name, desc: meta.desc as! DefaultDescription)
            //mTinode.updateUser(getName(), meta.desc);
        }
        // update listener
        listener?.onMetaDesc(desc: (meta.desc as! Description<DP, DR>))
    }
    private func removeSubFromCache(sub: Subscription<SP, SR>) {
        if var allsubs = subs {
            allsubs.removeValue(forKey: sub.user!)
        }
    }

    fileprivate func update(sub: Subscription<SP, SR>) {
        if description?.merge(sub: sub) ?? false {
            store?.topicUpdate(topic: self)
        }
        if sub.online != nil {
            self.online = sub.online!
        }
    }
    fileprivate func update(desc: Description<DP, DR>) {
        if description?.merge(desc: desc) ?? false {
            store?.topicUpdate(topic: self)
        }
        /*
        if description?.merge(sub: sub) ?? false {
            store?.topicUpdate(topic: self)
        }
        if sub.online != nil {
            self.online = sub.online!
        }
        */
    }
    fileprivate func update(tags: [String]) {
        self.tags = tags
        store?.topicUpdate(topic: self)
    }
    private func addSubToCache(sub: Subscription<SP, SR>) {
        if subs == nil {
            subs = [:]
        }
        subs![sub.user!] = sub
    }

    private func processSub(newsub: Subscription<SP, SR>) {
        var sub: Subscription<SP, SR>?
        if (newsub.deleted != nil) {
            store?.subDelete(topic: self, sub: newsub)
            removeSubFromCache(sub: newsub);
            
            sub = newsub;
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
    /*
    private func setMaxDel(maxDel: Int) {
        if maxDel > self.maxDel {
            self.maxDel = maxDel
        }
    }
    */
    private func routeMetaDel(clear: Int, delseq: [MsgDelRange]) {
        if let s = store {
            for range in delseq {
                s.msgDelete(topic: self, delete: clear, deleteFrom: range.low!, deleteTo: range.hi ?? (range.low! + 1))
            }
        }
        self.maxDel = clear
        //setMaxDel(maxDel: clear)
        listener?.onData(data: nil)
    }
    
    fileprivate func routeMetaSub(meta: MsgServerMeta) {
        print("routing sub")
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
    func routeMeta(meta: MsgServerMeta) {
        if meta.desc != nil {
            routeMetaDesc(meta: meta)
        }
        if meta.sub != nil {
            if subsUpdated == nil || (meta.ts != nil && subsUpdated! < meta.ts!) {
                subsLastUpdated = meta.ts!
            }
            self.routeMetaSub(meta: meta)
            /*
            if (mSubsUpdated == null || meta.ts.after(mSubsUpdated)) {
                mSubsUpdated = meta.ts;
            }
            routeMetaSub(meta);
            */
            print("handling subs")
        }
        if meta.del != nil {
            routeMetaDel(clear: meta.del!.clear, delseq: meta.del!.delseq)
            print("handle del")
        }
        if meta.tags != nil {
            routeMetaTags(tags: meta.tags!)
            print("handle tags")
        }
        // update listener
        listener?.onMeta(meta: meta)
    }
    private func noteReadRecv(what: NoteType) -> Int {
        var result = 0
        switch what {
        case .kRecv:
            let seq = description!.getSeq
            if description!.getRecv < seq {
                tinode!.noteRecv(topic: name, seq: seq)
                result = seq
                description!.recv = seq
            }
            break
        case .kRead:
            let seq = description!.getSeq
            if description!.getRead < seq {
                tinode!.noteRead(topic: name, seq: seq)
                result = seq
                description!.read = seq
            }
            break
        }
        return result
    }
    @discardableResult
    func noteRecv() -> Int {
        let result = noteReadRecv(what: NoteType.kRecv)
        store?.setRecv(topic: self, recv: result)
        return result
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
    func routeData(data: MsgServerData) {
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
    func getMeta(query: MsgGetMeta) -> PromisedReply<ServerMessage>? {
        return tinode?.getMeta(topic: name, query: query)
    }
    private func updateAccessMode(ac: AccessChange?) -> Bool {
        if description!.acs == nil {
            description!.acs = Acs(from: nil as Acs?)
        }
        return description!.acs!.update(from: ac)
    }
    func routeInfo(info: MsgServerInfo) {
        if info.what == Tinode.kNoteKp {
            if let sub = getSubscription(for: info.from) {
                switch info.what {
                case Tinode.kNoteRecv:
                    sub.recv = info.seq
                    store?.msgRecvByRemote(sub: sub, recv: info.seq)
                    break
                case Tinode.kNoteRead:
                    sub.read = info.seq
                    store?.msgReadByRemote(sub: sub, read: info.seq)
                    break
                default:
                    break
                }
            }
        }
        listener?.onInfo(info: info)
    }
    func routePres(pres: MsgServerPres) {
        let what = MsgServerPres.parseWhat(what: pres.what)
        //var sub: Subscription<SP, SR>? = nil
        switch what {
        case .kOn, .kOff:
            if let sub = getSubscription(for: pres.src) {
                sub.online = (.kOn == what)
            }
            break
        case .kDel:
            routeMetaDel(clear: pres.clear!, delseq: pres.delseq!)
            break
        case .kAcs:
            if let sub = getSubscription(for: pres.src) {
                sub.updateAccessMode(ac: pres.dacs)
                if sub.user == tinode?.myUid {
                    if self.updateAccessMode(ac: pres.dacs) {
                        print("updating store access mode")
                        store?.topicUpdate(topic: self)
                    }
                }
                print("sub acs =\(String(describing: sub.acs))")
                if !sub.acs!.isModeDefined {
                    print("sub.acs NOT DEFINED")
                    if isP2PType {
                        print("p2p - calling leave()")
                        _ = try? leave()
                    }
                    sub.deleted = Date()
                    processSub(newsub: sub)
                }
            } else {
                let acs = Acs(from: nil as Acs?)
                acs.update(from: pres.dacs)
                if acs.isModeDefined {
                    getMeta(query: getMetaGetBuilder().withGetSub(user: pres.src).build())
                }
            }
            break
        default:
            print("unknown presence type \(String(describing: pres.what))")
            break
        }
        listener?.onPres(pres: pres)
    }
    private func topicLeft(unsub: Bool?, code: Int?, reason: String?) {
        if attached {
            attached = false
            print("leaving \(name): \(String(describing: unsub)) \(String(describing: code)) \(String(describing: reason))")
            listener?.onLeave(unsub: unsub, code: code, text: reason)
        }
    }
    @discardableResult
    func leave(unsub: Bool? = false) throws -> PromisedReply<ServerMessage>? {
        if attached {
            return try tinode?.leave(topic: name, unsub: unsub)?
                .then(
                    onSuccess: { [weak self] msg in
                        //topicLeft()
                        if self == nil {
                            throw TinodeError.invalidState("Topic.self not available in result handler")
                        }
                        self!.topicLeft(unsub: unsub, code: msg.ctrl?.code, reason: msg.ctrl?.text)
                        if unsub ?? false {
                            self!.tinode?.unregisterTopic(topicName: self!.name)
                        }
                        return nil
                    }, onFailure: nil)
        }
        if tinode?.isConnected ?? false {
            throw TinodeError.notSubscribed("Can't leave topic that I'm not subscribed to \(name)")
        }
        throw TinodeError.notConnected("Leaving topic when Tinode is not connected.")
    }
    
    private func processDelivery(ctrl: MsgServerCtrl?, id: Int) {
        guard let ctrl = ctrl else {
            return
        }
        let seq = ctrl.getIntParam(for: "seq")!
        setSeq(seq: seq)
        if id > 0, let s = store {
            if s.msgDelivered(topic: self, dbMessageId: Int64(id),
                              timestamp: ctrl.ts, seq: seq) {
                setRecv(recv: seq)
            }
        } else {
            setRecv(recv: seq)
        }
        setRead(read: seq)
        store?.setRead(topic: self, read: seq)
    }
    func publish(content: String?, msgId: Int) throws -> PromisedReply<ServerMessage>? {
        return try tinode!.publish(topic: name, data: content)?.then(
            onSuccess: { [weak self] msg in
                self?.processDelivery(ctrl: msg.ctrl, id: msgId)
                return nil
            }, onFailure: { err in
                return nil
            })
    }
    func publish(content: String?) throws -> PromisedReply<ServerMessage>? {
        var id: Int = -1
        if let s = store, let c = content {
            // TODO: id should be Int64. Fix this!!!
            id = Int(s.msgSend(topic: self, data: c))
        }
        if attached {
            return try publish(content: content, msgId: id)
        } else {
            return try subscribe().then(
                onSuccess: { [weak self] msg in
                    return try self?.publish(content: content, msgId: id)
                },
                onFailure: nil)
        }
    }
}

typealias DefaultTopic = Topic<VCard, PrivateType, VCard, PrivateType>
typealias DefaultComTopic = ComTopic<VCard>
typealias DefaultMeTopic = MeTopic<VCard>
typealias DefaultFndTopic = FndTopic<VCard>

class MeTopic<DP: Codable>: Topic<DP, PrivateType, DP, PrivateType> {
    init(tinode: Tinode?, l: Listener?) throws {
        try super.init(tinode: tinode, name: Tinode.kTopicMe, l: l)
    }
    init(tinode: Tinode?, desc: Description<DP, PrivateType>) throws {
        try super.init(tinode: tinode, name: Tinode.kTopicMe, desc: desc)
    }
    override fileprivate func routeMetaSub(meta: MsgServerMeta) {
        print("topic me routemetasub")
        if let metaSubs = meta.sub as? Array<Subscription<DP, PrivateType>> {
            for sub in metaSubs {
                if let topic = tinode!.getTopic(topicName: sub.topic!) {
                    if sub.deleted != nil {
                        tinode!.unregisterTopic(topicName: sub.topic!)
                    } else {
                        print("updating \(topic.name)")
                        if let t = topic as? DefaultTopic {
                            t.update(sub: sub as! Subscription<VCard, PrivateType>)
                        } else if let t = topic as? DefaultMeTopic {
                            t.update(sub: sub as! Subscription<VCard, PrivateType>)
                        } /*else if let t = topic as? DefaultFndTopic {
                            t.update(sub: sub)
                        } */
                        else {
                            print("updable to update topic: \(topic)")
                            assert(false)
                        }
                        //topic.update(sub)
                        // topic.listener?.onContUpdate(sub)
                    }
                } else if sub.deleted == nil {
                    tinode!.registerTopic(topic: tinode!.newTopic(sub: sub))
                    print("registering new topic")
                }
            }
            // listener?.onMetaSub(sub)
        }
        // listener?.onSubsUpdated()
    }
}
class FndTopic<SP: Codable>: Topic<String, String, SP, Array<String>> {
    init(tinode: Tinode?) throws {
        try super.init(tinode: tinode, name: Tinode.kTopicMe)
    }
}

class ComTopic<DP: Codable>: Topic<DP, PrivateType, DP, PrivateType> {
    override init(tinode: Tinode?, name: String, l: Listener?) throws {
        try super.init(tinode: tinode, name: name, l: l)
    }
    override init(tinode: Tinode?, sub: Subscription<DP, PrivateType>) throws {
        try super.init(tinode: tinode, sub: sub)
    }
    override init(tinode: Tinode?, name: String, desc: Description<DP, PrivateType>) throws {
        try super.init(tinode: tinode, name: name, desc: desc)
    }
}
