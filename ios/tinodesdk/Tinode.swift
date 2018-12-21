//
//  Tinode.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation


enum TinodeJsonError: Error {
    case encode
    case decode
}

enum TinodeError: Error {
    case invalidReply(String)
    case invalidState(String)
    case notConnected(String)
    case serverResponseError(Int, String, String?)
    case notSubscribed(String)
}

class Tinode {
    public static let kTopicNew = "new"
    public static let kTopicMe = "me"
    public static let kTopicFnd = "fnd"
    public static let kTopicGrpPrefix = "grp"
    public static let kTopicUsrPrefix = "usr"

    public static let kNoteKp = "kp"
    public static let kNoteRead = "read"
    public static let kNoteRecv = "recv"
    
    let kProtocolVersion = "0"
    let kVersion = "0.15"
    let kLocale = Locale.current.languageCode!
    var deviceId: String = ""

    var appName: String
    var apiKey: String
    var connection: Connection?
    var nextMsgId = 1
    var futures: [String:PromisedReply<ServerMessage>] = [:]
    var serverVersion: String?
    var serverBuild: String?
    var connectedPromise: PromisedReply<ServerMessage>?
    var timeAdjustment: TimeInterval = 0
    var isConnectionAuthenticated = false
    var myUid: String?
    var deviceToken: String?
    var authToken: String?
    var nameCounter = 0
    var store: Storage? = nil
    var topicsLoaded = false

    var isConnected: Bool {
        get {
            if let c = connection, c.isConnected {
                return true
            }
            return false
        }
    }

    // String -> Topic
    var topics: [String: TopicProto] = [:]
    var users: [String: UserProto] = [:]
    
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .customRFC3339
        return encoder
    }()

    init(for appname: String, authenticateWith apiKey: String,
         persistDataIn store: Storage? = nil) {
        self.appName = appname
        self.apiKey = apiKey
        self.store = store
        self.myUid = self.store?.myUid
        self.deviceToken = self.store?.deviceToken
        //self.osVersoin
        
        // osVersion
        // eventListener
        // typeOfMetaPacket
        // futures
        // store
        // myUID
        // deviceToken
        loadTopics()
    }
    @discardableResult
    private func loadTopics() -> Bool {
        guard !topicsLoaded else { return true }
        if let s = store, s.isReady, let allTopics = s.topicGetAll(from: self) {
            for t in allTopics {
                t.store = s
                topics[t.name] = t
            }
            topicsLoaded = true
        }
        return topicsLoaded
    }
    func updateUser<DP: Decodable, DR: Decodable>(uid: String, desc: Description<DP, DR>) {
        if let user = users[uid] {
            
            print("found user \(user)")
            _ = (user as? User<DP>)?.merge(from: desc)
        } else {
            let user = User<DP>(uid: uid, desc: desc)
            users[uid] = user
            print("updating")
        }
        // store?.userUpdate(user)
    }
    func updateUser<DP: Decodable, DR: Decodable>(sub: Subscription<DP, DR>) {
        let uid = sub.user!
        if let user = users[uid] {
            _ = (user as? User<DP>)?.merge(from: sub)
        } else {
            let user = try! User<DP>(sub: sub)
            users[uid] = user
        }
        // store?.userUpdate(user)
    }

    func nextUniqueString() -> String {
        nameCounter += 1
        let millisecSince1970 = Int64( (Date().timeIntervalSince1970 as Double) * 1000)
        let q = millisecSince1970.advanced(by: -1414213562373) << 16
        let v = q.advanced(by: nameCounter & 0xffff)
        return String(v, radix: 32)
    }

    private func getUserAgent() -> String {
        return "\(appName) (locale \(kLocale)); tinode-iOS/\(kVersion)"
    }
    
    private func getNextMsgId() -> String {
        nextMsgId += 1
        return String(nextMsgId)
    }
    
    private func send(payload data: Data) throws {
        guard connection != nil else {
            throw TinodeError.notConnected("Attempted to send msg to a closed connection.")
        }
        connection!.send(payload: data)
    }

    private func resolveWithPacket(id: String?, pkt: ServerMessage) throws {
        if let idUnwrapped = id {
            let p = futures.removeValue(forKey: idUnwrapped)
            if let r = p, !r.isDone {
                try r.resolve(result: pkt)
            }
        }
    }
    private func dispatch(_ msg: String) throws {
        guard !msg.isEmpty else {
            return
        }

        let jsonDecoder = JSONDecoder()
        guard let data = msg.data(using: .utf8) else {
            throw TinodeJsonError.decode
        }
        jsonDecoder.dateDecodingStrategy = .customRFC3339
        let serverMsg = try jsonDecoder.decode(ServerMessage.self, from: data)
        print("serverMsg = \(serverMsg)")
        
        if let ctrl = serverMsg.ctrl {
            // Listener.onCtrlMessage
            if let id = ctrl.id {
                if let r = futures.removeValue(forKey: id) {
                    if ctrl.code >= 200 && ctrl.code < 400 {
                        try r.resolve(result: serverMsg)
                    } else {
                        try r.reject(error: TinodeError.serverResponseError(
                            ctrl.code, ctrl.text, ctrl.getStringParam(for: "what")))
                    }
                }
                print("ctrl.id = \(id)")
            }
            if let what = ctrl.getStringParam(for: "what"), what == "data" {
                if let topic = ctrl.topic, let t = getTopic(topicName: topic) {
                    t.allMessagesReceived(count: ctrl.getIntParam(for: "count"))
                }
                print("what = \(what)")
            }
        } else if let meta = serverMsg.meta {
            if let t = getTopic(topicName: meta.topic!) {
                //t.route
                t.routeMeta(meta: meta)
            } else {
                _ = maybeCreateTopic(meta: meta)
                print("maybe create \(String(describing: meta.topic))")
            }
            // update listener
            try resolveWithPacket(id: meta.id, pkt: serverMsg)
            //if t != nil
        } else if let data = serverMsg.data {
            if let t = getTopic(topicName: data.topic!) {
                t.routeData(data: data)
            }
            // listener?.onDataMessage(data)
            try resolveWithPacket(id: data.id, pkt: serverMsg)
        } else if let pres = serverMsg.pres {
            if let topicName = pres.topic {
                if let t = getTopic(topicName: topicName) {
                    t.routePres(pres: pres)
                    if topicName == Tinode.kTopicMe, case .p2p = DefaultTopic.topicTypeByName(name: pres.src) {
                        if let forwardTo = getTopic(topicName: pres.src!) {
                            forwardTo.routePres(pres: pres)
                        }
                    }
                }
            }
            //listener?.onPresMessage(pres)
        } else if let info = serverMsg.info {
            if let topicName = info.topic {
                if let t = getTopic(topicName: topicName) {
                    t.routeInfo(info: info)
                }
                // listener?.onInfoMessage(info)
            }
        }
    }
    private func note(topic: String, what: String, seq: Int) {
        let msg = ClientMessage<Int, Int>(
            note: MsgClientNote(topic: topic, what: what, seq: seq))
        do {
            let jsonData = try Tinode.jsonEncoder.encode(msg)
            let jd = String(decoding: jsonData, as: UTF8.self)
            print("note request: \(jd)")
            connection!.send(payload: jsonData)
        } catch {
        }
    }
    func noteRecv(topic: String, seq: Int) {
        note(topic: topic, what: Tinode.kNoteRecv, seq: seq)
    }
    func noteRead(topic: String, seq: Int) {
        note(topic: topic, what: Tinode.kNoteRead, seq: seq)
    }
    func noteKeyPress(topic: String) {
        note(topic: topic, what: Tinode.kNoteKp, seq: 0)
    }
    
    private func hello() throws -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(
            hi: MsgClientHi(id: msgId, ver: kVersion,
                            ua: getUserAgent(), dev: deviceId,
                            lang: kLocale))
        do {
            var reply = PromisedReply<ServerMessage>()
            futures[msgId] = reply
            //reply =
            reply = try reply.then(onSuccess: { [weak self] pkt in
                guard let ctrl = pkt.ctrl else {
                    throw TinodeError.invalidReply("Unexpected type of reply packet to hello")
                }
                if !(ctrl.params?.isEmpty ?? true) {
                    self?.serverVersion = ctrl.getStringParam(for: "ver")
                    self?.serverBuild = ctrl.getStringParam(for: "build")
                }
                return nil
            }, onFailure: nil)!
            let jsonData = try Tinode.jsonEncoder.encode(msg)
            connection!.send(payload: jsonData)
            return reply
        } catch {
            return nil
        }
    }
    func registerTopic(topic: TopicProto) {
        if !topic.isPersisted {
            store?.topicAdd(topic: topic)
        }
        topic.store = store
        topics[topic.name] = topic
    }
    func unregisterTopic(topicName: String) {
        //Topic topic = mTopics.remove(topicName);
        if let t = topics.removeValue(forKey: topicName) {
            // todo: clean up storate
            print("unregistering \(t)")
            t.store = nil
            store?.topicDelete(topic: t)
        }
    }
    func newTopic<SP: Codable, SR: Codable>(sub: Subscription<SP, SR>) -> TopicProto {
        if sub.topic == Tinode.kTopicMe {
            let t = try! MeTopic<SP>(tinode: self, l: nil)
            return t
        } else if sub.topic == Tinode.kTopicFnd {
            let r = try! FndTopic<SP>(tinode: self)
            return r
        }
        return try! ComTopic<SP>(tinode: self, sub: sub as! Subscription<SP, PrivateType>)
    }
    func maybeCreateTopic(meta: MsgServerMeta) -> TopicProto? {
        if meta.desc == nil {
            return nil
        }
        
        var topic: TopicProto?
        if meta.topic == Tinode.kTopicMe {
            topic = try! DefaultMeTopic(tinode: self, desc: meta.desc! as! DefaultDescription)
        } else if meta.topic == Tinode.kTopicFnd {
            topic = try! DefaultFndTopic(tinode: self)
        } else {
            topic = try! DefaultComTopic(tinode: self, name: meta.topic!, desc: meta.desc! as! DefaultDescription)
        }
        registerTopic(topic: topic!)
        return topic
    }
    func changeTopicName(topic: TopicProto, oldName: String) -> Bool {
        let result = topics.removeValue(forKey: oldName) != nil
        registerTopic(topic: topic)
        return result
    }
    func getMeTopic() -> DefaultMeTopic? {
        return getTopic(topicName: Tinode.kTopicMe) as? DefaultMeTopic
    }
    func getTopic(topicName: String) -> TopicProto? {
        if topicName.isEmpty {
            return nil
        }
        return topics[topicName]
    }
    func loginBasic(uname: String, password: String) throws -> PromisedReply<ServerMessage> {
        return try login(scheme: AuthScheme.kLoginBasic,
                         secret: AuthScheme.encodeBasicToken(
                            uname: uname, password: password),
                         creds: nil)
    }
    func login(scheme: String, secret: String, creds: [Credential]?) throws -> PromisedReply<ServerMessage> {
        // handle auto login
        if isConnectionAuthenticated {
            // Already logged in.
            //return PromisedReply<ServerMessage>(value: nil)
            return PromisedReply<ServerMessage>()
        }
        
        let msgId = getNextMsgId()
        let msgl = MsgClientLogin(id: msgId, scheme: scheme, secret: secret, credentials: nil)
        if let creds = creds, creds.count > 0 {
            for c in creds {
                msgl.addCred(c: c)
            }
        }
        let msg = ClientMessage<Int, Int>(login: msgl)
        let jsonData = try! Tinode.jsonEncoder.encode(msg)
        let jd = String(decoding: jsonData, as: UTF8.self)
        print("about to send \(jd)")
        connection!.send(payload: jsonData)
        var future = PromisedReply<ServerMessage>()
        futures[msgId] = future
        future = try future.then(onSuccess: { [weak self] pkt in
            try self?.loginSuccessful(ctrl: pkt.ctrl)
            return nil
        }, onFailure: { [weak self] err in
            if let e = err as? TinodeError {
                if case TinodeError.serverResponseError(let code, _, _) = e {
                    if code >= 400 && code < 500 {
                        // todo:
                        // clear auth data.
                    }
                    self?.isConnectionAuthenticated = false
                }
                // todo: update listener
                
            }
            return PromisedReply<ServerMessage>(error: err)
        })!
        return future
        //send(Tinode.getJsonMapper().writeValueAsString(msg));
    }
    
    private func loginSuccessful(ctrl: MsgServerCtrl?) throws {
        guard let ctrl = ctrl else {
            throw TinodeError.invalidReply("Unexpected type of server response")
        }
        let newUid = ctrl.getStringParam(for: "user")
        if let curUid = myUid, curUid != newUid {
            // todo:
            // logout
            // uid mismatch
            return
        }
        myUid = newUid
        store?.myUid = newUid
        // Load topics if not yet loaded.
        loadTopics()
        authToken = ctrl.getStringParam(for: "token")
        // auth expires
        if ctrl.code < 300 {
            isConnectionAuthenticated = true
            // todo: listener
        }
    }
    private func disconnect() {
        // setAutologin(false)
        connection?.disconnect()
    }
    func logout() {
        disconnect()
        myUid = nil
        store?.logout()
    }
    /*
    private func loadTopics() {
        //
    }
    */
    private func handleDisconnect(isServerOriginated: Bool, code: Int, reason: String) {
        futures.removeAll()
        serverBuild = nil
        serverVersion = nil
        isConnectionAuthenticated = false
        // todo:
        // iterate over topics: topicLeft
        // listener on disconnect
    }
    class TinodeConnectionListener : ConnectionListener {
        var tinode: Tinode
        init(tinode: Tinode) {
            self.tinode = tinode
        }
        func onConnect() -> Void {
            print("tinode connected")
            do {
                var _ = try tinode.hello()?.then(onSuccess: { [weak self] pkt in
                    guard self != nil else {
                        throw TinodeError.invalidState("Missing Tinode instance in connection handler")
                    }
                    let tinode = self!.tinode
                    if let connected = tinode.connectedPromise, !connected.isDone {
                        try connected.resolve(result: pkt)
                    }
                    tinode.timeAdjustment = Date().timeIntervalSince(pkt.ctrl!.ts)
                    // tinode store
                    tinode.store?.setTimeAdjustment(adjustment: tinode.timeAdjustment)
                    // listener
                    return nil
                }, onFailure: nil)
                // todo: auto login & credentials
            } catch {
                print("onConnect error \(error)")
            }
        }
        func onMessage(with message: String) -> Void {
            print("tinode message \(message)")
            do {
                try tinode.dispatch(message)
            } catch {
                print("onMessage error: \(error)")
            }
        }
        func onDisconnect(isServerOriginated: Bool, code: Int, reason: String) -> Void {
            print("tinode on disconnect")
            tinode.handleDisconnect(isServerOriginated: isServerOriginated, code: code, reason: reason)
        }
        func onError(error: Error) -> Void {
            tinode.handleDisconnect(isServerOriginated: true, code: 0, reason: error.localizedDescription)
            print("tinode error: \(error)")
            if let connected = tinode.connectedPromise, !connected.isDone {
                do {
                    try connected.reject(error: error)
                } catch {
                    // Do nothing.
                }
            }
        }
    }
    public func connect(to hostName: String, useTLS: Bool) throws -> PromisedReply<ServerMessage>? {
        if isConnected {
            print("tinode is already connected: \(isConnected)")
            return nil
        }
        //let useTLS = false
        let scheme = "ws" // useTLS ? "wss" : "ws"
        let urlString = "\(scheme)://\(hostName)/v\(kProtocolVersion)/"
        let endpointURL: URL = URL(string: urlString)!
        connection = Connection(open: endpointURL,
                                with: apiKey,
                                notify: TinodeConnectionListener(tinode: self))
        connectedPromise = PromisedReply<ServerMessage>()
        try connection?.connect()
        return connectedPromise
    }
    
    public func subscribe<Pu, Pr>(to topicName: String,
                                  set: MsgSetMeta<Pu, Pr>?,
                                  get: MsgGetMeta?) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Pu, Pr>(
            sub: MsgClientSub(
                id: msgId,
                topic: topicName,
                set: set,
                get: get))
        let reply = PromisedReply<ServerMessage>()
        futures[msgId] = reply
        do {
            let jsonData = try Tinode.jsonEncoder.encode(msg)
            let jd = String(decoding: jsonData, as: UTF8.self)
            print("subscribe request: \(jd)")
            connection!.send(payload: jsonData)
            
        } catch {
            // ???
            futures.removeValue(forKey: msgId)
            // TODO: return nil here
            //return nil
            
        }
        return reply
    }
    
    public func getMeta(topic: String, query: MsgGetMeta) -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(  // generic params don't matter
            get: MsgClientGet(
                id: msgId,
                topic: topic,
                query: query))
        let reply = PromisedReply<ServerMessage>()
        futures[msgId] = reply
        do {
            let jsonData = try Tinode.jsonEncoder.encode(msg)
            let jd = String(decoding: jsonData, as: UTF8.self)
            print("get request: \(jd)")
            connection!.send(payload: jsonData)
            
        } catch {
            // ???
            futures.removeValue(forKey: msgId)
            return nil
            
        }
        return reply
    }
    public func leave(topic: String, unsub: Bool?) -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(
            leave: MsgClientLeave(id: msgId, topic: topic, unsub: unsub))
        let reply = PromisedReply<ServerMessage>()
        futures[msgId] = reply
        do {
            let jsonData = try Tinode.jsonEncoder.encode(msg)
            let jd = String(decoding: jsonData, as: UTF8.self)
            print("leave request: \(jd)")
            connection!.send(payload: jsonData)
        } catch {
            futures.removeValue(forKey: msgId)
            return nil
        }
        return reply
    }
    public func publish(topic: String, data: String?) -> PromisedReply<ServerMessage>? {
        //ClientMessage msg = new ClientMessage(new MsgClientLeave(getNextId(), topicName, unsub)
        let content = data != nil ? JSONValue.string(data!) : nil
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(
            pub: MsgClientPub(id: msgId, topic: topic, noecho: true, head: nil, content: content))
        let reply = PromisedReply<ServerMessage>()
        futures[msgId] = reply
        do {
            let jsonData = try Tinode.jsonEncoder.encode(msg)
            let jd = String(decoding: jsonData, as: UTF8.self)
            print("leave request: \(jd)")
            connection!.send(payload: jsonData)
        } catch {
            futures.removeValue(forKey: msgId)
            return nil
        }
        return reply
    }

    func getFilteredTopics(type: TopicType, updated: Date?) -> Array<TopicProto>? {
        if case .any = type, updated == nil {
            return topics.values.compactMap { $0 }
        }
        if case .unknown = type {
            return nil
        }
        let r = topics.values.filter { (topic) -> Bool in
            //let intType = case let topic.topicType
            let tr = topic.topicType.rawValue
            let tr2 = type.rawValue
            if (tr & tr2) != 0 && (updated == nil || updated! < topic.updated!) {
                return true
            }
            return false
        }
        return r
    }
}
