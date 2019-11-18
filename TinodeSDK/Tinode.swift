//
//  Tinode.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation


public enum TinodeJsonError: Error {
    case encode
    case decode
}

public enum TinodeError: LocalizedError, CustomStringConvertible {
    case invalidReply(String)
    case invalidState(String)
    case notConnected(String)
    case serverResponseError(Int, String, String?)
    case notSubscribed(String)
    case notSynchronized

    public var description: String {
        get {
            switch self {
            case .invalidReply(let message):
                return "Invalid reply: \(message)"
            case .invalidState(let message):
                return "Invalid state: \(message)"
            case .notConnected(let message):
                return "Not connected: \(message)"
            case .serverResponseError(let code, let text, _):
                return "\(text) (\(code))"
            case .notSubscribed(let message):
                return "Not subscribed: \(message)"
            case .notSynchronized:
                return "Not synchronized"
            }
        }
    }

    public var errorDescription: String? {
        return description
    }
}

// Callback interface called by Connection
// when it receives events from the websocket.
public protocol TinodeEventListener: class {
    // Connection established successfully, handshakes exchanged.
    // The connection is ready for login.
    // Params:
    //   code   should be always 201.
    //   reason should be always "Created".
    //   params server parameters, such as protocol version.
    func onConnect(code: Int, reason: String, params: [String:JSONValue]?)

    // Connection was dropped.
    // Params:
    //   byServer: true if connection was closed by server.
    //   code: numeric code of the error which caused connection to drop.
    //   reason: error message.
    func onDisconnect(byServer: Bool, code: Int, reason: String)

    // Result of successful or unsuccessful {@link #login} attempt.
    // Params:
    //   code: a numeric value between 200 and 299 on success, 400 or higher on failure.
    //   text: "OK" on success or error message.
    func onLogin(code: Int, text: String)

    // Handle generic server message.
    // Params:
    //   msg: message to be processed.
    func onMessage(msg: ServerMessage?)

    // Handle unparsed message. Default handler calls {@code #dispatchPacket(...)} on a
    // websocket thread.
    // A subclassed listener may wish to call {@code dispatchPacket()} on a UI thread
    // Params:
    //   msg: message to be processed.
    func onRawMessage(msg: String)

    // Handle control message
    // Params:
    //   ctrl: control message to process.
    func onCtrlMessage(ctrl: MsgServerCtrl?)

    // Handle data message
    // Params:
    //   data: control message to process.
    func onDataMessage(data: MsgServerData?)

    // Handle info message
    // Params:
    //   info: info message to process.
    func onInfoMessage(info: MsgServerInfo?)

    // Handle meta message
    // Params:
    //   meta: meta message to process.
    func onMetaMessage(meta: MsgServerMeta?)

    // Handle presence message
    // Params:
    //   pres: control message to process.
    func onPresMessage(pres: MsgServerPres?)
}

public class Tinode {
    public static let kTopicNew = "new"
    public static let kUserNew = "new"
    public static let kTopicMe = "me"
    public static let kTopicFnd = "fnd"
    public static let kTopicSys = "sys"

    public static let kTopicGrpPrefix = "grp"
    public static let kTopicUsrPrefix = "usr"

    public static let kNoteKp = "kp"
    public static let kNoteRead = "read"
    public static let kNoteRecv = "recv"
    public static let kNullValue = "\u{2421}"
    internal static let log = Log(subsystem: "co.tinode.tinodesdk")

    let kProtocolVersion = "0"
    let kVersion = "0.16"
    let kLibVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    let kLocale = Locale.current.languageCode!
    public var OsVersion: String = ""

    private class ConcurrentFuturesMap {
        static let kFutureExpiryInterval = 3.0
        static let kFutureExpiryTimerTolerance = 0.2
        static let kFutureTimeout = 5.0
        private var futuresDict = [String:PromisedReply<ServerMessage>]()
        private let queue = DispatchQueue(label: "co.tinode.futuresmap")
        private var timer: Timer?
        init() {
            timer = Timer(
                timeInterval: ConcurrentFuturesMap.kFutureExpiryInterval,
                target: self,
                selector: #selector(expireFutures),
                userInfo: nil,
                repeats: true)
            timer!.tolerance = ConcurrentFuturesMap.kFutureExpiryTimerTolerance
            // Run on the background thread.
            DispatchQueue.global(qos: .background).async {
                let runLoop = RunLoop.current
                runLoop.add(self.timer!, forMode: .common)
                runLoop.run()
            }
        }
        deinit {
            timer!.invalidate()
        }
        @objc private func expireFutures() {
            queue.sync {
                let expirationThreshold = Date().addingTimeInterval(TimeInterval(-ConcurrentFuturesMap.kFutureTimeout))
                let error = TinodeError.serverResponseError(504, "timeout", nil)
                var expiredKeys = [String]()
                for (id, f) in futuresDict {
                    if f.creationTimestamp < expirationThreshold {
                        try? f.reject(error: error)
                        expiredKeys.append(id)
                    }
                }
                for id in expiredKeys {
                    futuresDict.removeValue(forKey: id)
                }
            }
        }
        subscript(key: String) -> PromisedReply<ServerMessage>? {
            get { return queue.sync { return futuresDict[key] } }
            set { queue.sync { futuresDict[key] = newValue } }
        }
        func removeValue(forKey key: String) -> PromisedReply<ServerMessage>? {
            return queue.sync { return futuresDict.removeValue(forKey: key) }
        }
        func rejectAndPurgeAll(withError e: Error) {
            queue.sync {
                for f in futuresDict.values {
                    try? f.reject(error: e)
                }
                futuresDict.removeAll()
            }
        }
    }

    // Forwards events to all subscribed listeners.
    private class ListenerNotifier: TinodeEventListener {
        private var listeners: [TinodeEventListener] = []
        private var queue = DispatchQueue(label: "co.tinode.listener")

        public func addListener(_ l: TinodeEventListener) {
            queue.sync {
                guard listeners.firstIndex(where: { $0 === l }) == nil else { return }
                listeners.append(l)
            }
        }

        public func removeListener(_ l: TinodeEventListener) {
            queue.sync {
                if let idx = listeners.firstIndex(where: { $0 === l }) {
                    listeners.remove(at: idx)
                }
            }
        }

        public var listenersThreadSafe: [TinodeEventListener] {
            queue.sync { return self.listeners }
        }

        func onConnect(code: Int, reason: String, params: [String : JSONValue]?) {
            listenersThreadSafe.forEach { $0.onConnect(code: code, reason: reason, params: params) }
        }

        func onDisconnect(byServer: Bool, code: Int, reason: String) {
            listenersThreadSafe.forEach { $0.onDisconnect(byServer: byServer, code: code, reason: reason) }
        }

        func onLogin(code: Int, text: String) {
            listenersThreadSafe.forEach { $0.onLogin(code: code, text: text) }
        }

        func onMessage(msg: ServerMessage?) {
            listenersThreadSafe.forEach { $0.onMessage(msg: msg) }
        }

        func onRawMessage(msg: String) {
            listenersThreadSafe.forEach { $0.onRawMessage(msg: msg) }
        }

        func onCtrlMessage(ctrl: MsgServerCtrl?) {
            listenersThreadSafe.forEach { $0.onCtrlMessage(ctrl: ctrl) }
        }

        func onDataMessage(data: MsgServerData?) {
            listenersThreadSafe.forEach { $0.onDataMessage(data: data) }
        }

        func onInfoMessage(info: MsgServerInfo?) {
            listenersThreadSafe.forEach { $0.onInfoMessage(info: info) }
        }

        func onMetaMessage(meta: MsgServerMeta?) {
            listenersThreadSafe.forEach { $0.onMetaMessage(meta: meta) }
        }

        func onPresMessage(pres: MsgServerPres?) {
            listenersThreadSafe.forEach { $0.onPresMessage(pres: pres) }
        }
    }
    public var appName: String
    public var apiKey: String
    public var useTLS: Bool
    public var hostName: String
    public var connection: Connection?
    public var nextMsgId = 1
    private var futures = ConcurrentFuturesMap()
    public var serverVersion: String?
    public var serverBuild: String?
    public var connectedPromise: PromisedReply<ServerMessage>?
    public var timeAdjustment: TimeInterval = 0
    public var isConnectionAuthenticated = false
    public var myUid: String?
    public var deviceToken: String?
    public var authToken: String?
    public var nameCounter = 0
    public var store: Storage? = nil
    private var listenerNotifier = ListenerNotifier()
    public var topicsLoaded = false
    private(set) public var topicsUpdated: Date? = nil

    struct LoginCredentials {
        let scheme: String
        let secret: String
        init(using scheme: String, authenticateWith secret: String) {
            self.scheme = scheme
            self.secret = secret
        }
    }
    private var loginCredentials: LoginCredentials? = nil
    private var autoLogin: Bool = false
    private var loginInProgress: Bool = false

    public func baseURL(useWebsocketProtocol: Bool) -> URL? {
        guard !hostName.isEmpty else { return nil }
        return hostURL(useWebsocketProtocol: useWebsocketProtocol)?.appendingPathComponent("v\(kProtocolVersion)")
    }
    public func hostURL(useWebsocketProtocol: Bool) -> URL? {
        guard !hostName.isEmpty else { return nil }
        let protocolString = useTLS ? (useWebsocketProtocol ? "wss://" : "https://") : (useWebsocketProtocol ? "ws://" : "http://")
        let urlString = "\(protocolString)\(hostName)/"
        return URL(string: urlString)
    }
    public func channelsURL(useWebsocketProtocol: Bool) -> URL? {
        guard var b = baseURL(useWebsocketProtocol: useWebsocketProtocol) else { return nil }
        b.appendPathComponent("/channels")
        return b
    }
    public var isConnected: Bool {
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

    public static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        encoder.dateEncodingStrategy = .customRFC3339
        return encoder
    }()
    public static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        decoder.dateDecodingStrategy = .customRFC3339
        return decoder
    }()

    public init(for appname: String, authenticateWith apiKey: String,
         persistDataIn store: Storage? = nil,
         fowardEventsTo l: TinodeEventListener? = nil) {
        self.appName = appname
        self.apiKey = apiKey
        self.store = store
        if let listener = l {
            self.listenerNotifier.addListener(listener)
        }
        self.myUid = self.store?.myUid
        self.deviceToken = self.store?.deviceToken
        self.useTLS = false
        self.hostName = ""
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

    public func addListener(_ l: TinodeEventListener) {
        listenerNotifier.addListener(l)
    }
    public func removeListener(_ l: TinodeEventListener) {
        listenerNotifier.removeListener(l)
    }

    @discardableResult
    private func loadTopics() -> Bool {
        guard !topicsLoaded else { return true }
        if let s = store, s.isReady, let allTopics = s.topicGetAll(from: self) {
            for t in allTopics {
                t.store = s
                topics[t.name] = t
                if let updated = t.updated {
                    if topicsUpdated == nil || topicsUpdated! < updated {
                        topicsUpdated = updated
                    }
                }
            }
            topicsLoaded = true
        }
        return topicsLoaded
    }
    public func isMe(uid: String?) -> Bool {
        return self.myUid == uid
    }
    public func updateUser<DP: Codable, DR: Codable>(uid: String, desc: Description<DP, DR>) {
        var userPtr: UserProto?
        if let user = users[uid] {
            _ = (user as? User<DP>)?.merge(from: desc)
            userPtr = user
        } else {
            let user = User<DP>(uid: uid, desc: desc)
            users[uid] = user
            userPtr = user
        }
        store?.userUpdate(user: userPtr!)
    }
    public func updateUser<DP: Codable, DR: Codable>(sub: Subscription<DP, DR>) {
        var userPtr: UserProto?
        let uid = sub.user!
        if let user = users[uid] {
            _ = (user as? User<DP>)?.merge(from: sub)
            userPtr = user
        } else {
            let user = try! User<DP>(sub: sub)
            users[uid] = user
            userPtr = user
        }
        store?.userUpdate(user: userPtr!)
    }
    public func getUser<SP: Codable>(with uid: String) -> User<SP>? {
        if let user = users[uid] {
            return user as? User<SP>
        }
        if let user = store?.userGet(uid: uid) {
            users[uid] = user
            return user as? User<SP>
        }
        return nil
    }

    public func nextUniqueString() -> String {
        nameCounter += 1
        let millisecSince1970 = Int64(Date().timeIntervalSince1970 as Double * 1000)
        let q = ((millisecSince1970 - 1414213562373) << 16).advanced(by: nameCounter & 0xffff)
        return String(q, radix: 32)
    }

    public var userAgent: String {
        get {
            return "\(appName) (iOS \(OsVersion); \(kLocale)); tinode-swift/\(kLibVersion)"
        }
    }

    private func getNextMsgId() -> String {
        nextMsgId += 1
        return String(nextMsgId)
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

        listenerNotifier.onRawMessage(msg: msg)
        guard let data = msg.data(using: .utf8) else {
            throw TinodeJsonError.decode
        }
        let serverMsg = try Tinode.jsonDecoder.decode(ServerMessage.self, from: data)

        listenerNotifier.onMessage(msg: serverMsg)

        if let ctrl = serverMsg.ctrl {
            listenerNotifier.onCtrlMessage(ctrl: ctrl)
            if let id = ctrl.id {
                if let r = futures.removeValue(forKey: id) {
                    if ctrl.code >= 200 && ctrl.code < 400 {
                        try r.resolve(result: serverMsg)
                    } else {
                        try r.reject(error: TinodeError.serverResponseError(ctrl.code, ctrl.text, ctrl.getStringParam(for: "what")))
                    }
                }
            }
            if ctrl.code == 205 && ctrl.text == "evicted" {
                if let topicName = ctrl.topic, let topic = getTopic(topicName: topicName) {
                    topic.topicLeft(unsub: ctrl.getBoolParam(for: "unsub") ?? false, code: ctrl.code, reason: ctrl.text)
                }
            } else if let what = ctrl.getStringParam(for: "what"), let topicName = ctrl.topic, let topic = getTopic(topicName: topicName) {
                switch what {
                case "data":
                    topic.allMessagesReceived(count: ctrl.getIntParam(for: "count"))
                case "sub":
                    topic.allSubsReceived()
                default:
                    break
                }
            }
        } else if let meta = serverMsg.meta {
            if let t = getTopic(topicName: meta.topic!) ?? maybeCreateTopic(meta: meta) {
                t.routeMeta(meta: meta)

                if let updated = t.updated, t.topicType != .fnd, t.topicType != .me {
                    if topicsUpdated ?? Date.distantPast < updated {
                        topicsUpdated = updated
                    }
                }
            }

            listenerNotifier.onMetaMessage(meta: meta)
            try resolveWithPacket(id: meta.id, pkt: serverMsg)
            //if t != nil
        } else if let data = serverMsg.data {
            if let t = getTopic(topicName: data.topic!) {
                t.routeData(data: data)
            }
            listenerNotifier.onDataMessage(data: data)
            try resolveWithPacket(id: data.id, pkt: serverMsg)
        } else if let pres = serverMsg.pres {
            if let topicName = pres.topic {
                if let t = getTopic(topicName: topicName) {
                    t.routePres(pres: pres)
                    if topicName == Tinode.kTopicMe, case .p2p = Tinode.topicTypeByName(name: pres.src) {
                        if let forwardTo = getTopic(topicName: pres.src!) {
                            forwardTo.routePres(pres: pres)
                        }
                    }
                }
            }
            listenerNotifier.onPresMessage(pres: pres)
        } else if let info = serverMsg.info {
            if let topicName = info.topic {
                if let t = getTopic(topicName: topicName) {
                    t.routeInfo(info: info)
                }
                listenerNotifier.onInfoMessage(info: info)
            }
        }
    }
    private func note(topic: String, what: String, seq: Int) {
        let msg = ClientMessage<Int, Int>(
            note: MsgClientNote(topic: topic, what: what, seq: seq))
        try? send(payload: msg)
    }
    public func noteRecv(topic: String, seq: Int) {
        note(topic: topic, what: Tinode.kNoteRecv, seq: seq)
    }
    public func noteRead(topic: String, seq: Int) {
        note(topic: topic, what: Tinode.kNoteRead, seq: seq)
    }
    public func noteKeyPress(topic: String) {
        note(topic: topic, what: Tinode.kNoteKp, seq: 0)
    }
    private func send<DP: Codable, DR: Codable>(payload msg: ClientMessage<DP,DR>) throws {
        guard let conn = connection else {
            throw TinodeError.notConnected("Attempted to send msg to a closed connection.")
        }
        let jsonData = try Tinode.jsonEncoder.encode(msg)
        Tinode.log.debug("out: %@", String(decoding: jsonData, as: UTF8.self))
        conn.send(payload: jsonData)
    }
    private func sendWithPromise<DP: Codable, DR: Codable>(
        payload msg: ClientMessage<DP,DR>, with id: String) -> PromisedReply<ServerMessage> {
        let future = PromisedReply<ServerMessage>()
        do {
            try send(payload: msg)
            futures[id] = future
        } catch {
            do {
                try future.reject(error: error)
            } catch {
                Tinode.log.error("Error rejecting promise: %@", error.localizedDescription)
            }
        }
        return future
    }
    private func hello() -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(hi: MsgClientHi(id: msgId, ver: kVersion, ua: userAgent, dev: deviceToken, lang: kLocale))
        return try! sendWithPromise(payload: msg, with: msgId).thenApply(
            onSuccess: { [weak self] pkt in
                guard let ctrl = pkt?.ctrl else {
                    throw TinodeError.invalidReply("Unexpected type of reply packet to hello")
                }
                if !(ctrl.params?.isEmpty ?? true) {
                    self?.serverVersion = ctrl.getStringParam(for: "ver")
                    self?.serverBuild = ctrl.getStringParam(for: "build")
                }
                return nil
            })
    }

    /**
     * Start tracking topic: add it to in-memory cache.
     */
    public func startTrackingTopic(topic: TopicProto) {
        topic.store = store
        topics[topic.name] = topic
    }

    /**
     * Stop tracking the topic: remove it from in-memory cache.
     */
    public func stopTrackingTopic(topicName: String) {
        topics.removeValue(forKey: topicName)
    }

    /**
     * Check if topic is being tracked.
     */
    public func isTopicTracked(topicName: String) -> Bool {
        return topics[topicName] != nil
    }

    public func newTopic<SP: Codable & Mergeable, SR: Codable>(sub: Subscription<SP, SR>) -> TopicProto {
        if sub.topic == Tinode.kTopicMe {
            let t = MeTopic<SP>(tinode: self, l: nil)
            return t
        } else if sub.topic == Tinode.kTopicFnd {
            let r = FndTopic<SP>(tinode: self)
            return r
        }
        return ComTopic<SP>(tinode: self, sub: sub as! Subscription<SP, PrivateType>)
    }
    public static func newTopic(withTinode tinode: Tinode?,
                                forTopic name: String,
                                withListener listener: DefaultTopic.Listener?) -> TopicProto {
        if name == Tinode.kTopicMe {
            return DefaultMeTopic(tinode: tinode, l: listener)
        }
        if name == Tinode.kTopicFnd {
            return DefaultFndTopic(tinode: tinode)
        }
        return DefaultComTopic(tinode: tinode, name: name, l: listener)
    }
    public func newTopic(for name: String, with listener: DefaultTopic.Listener?) -> TopicProto {
        return Tinode.newTopic(withTinode: self, forTopic: name, withListener: listener)
    }
    public func maybeCreateTopic(meta: MsgServerMeta) -> TopicProto? {
        if meta.desc == nil {
            return nil
        }

        var topic: TopicProto?
        if meta.topic == Tinode.kTopicMe {
            topic = DefaultMeTopic(tinode: self, desc: meta.desc! as! DefaultDescription)
        } else if meta.topic == Tinode.kTopicFnd {
            topic = DefaultFndTopic(tinode: self)
        } else {
            topic = DefaultComTopic(tinode: self, name: meta.topic!, desc: meta.desc! as! DefaultDescription)
        }

        return topic
    }
    public func changeTopicName(topic: TopicProto, oldName: String) -> Bool {
        let result = topics.removeValue(forKey: oldName) != nil
        topics[topic.name] = topic
        store!.topicUpdate(topic: topic)
        return result
    }
    public func getMeTopic() -> DefaultMeTopic? {
        return getTopic(topicName: Tinode.kTopicMe) as? DefaultMeTopic
    }
    public func getOrCreateFndTopic() -> DefaultFndTopic {
        if let fnd = getTopic(topicName: Tinode.kTopicFnd) as? DefaultFndTopic {
            return fnd
        }
        return DefaultFndTopic(tinode: self)
    }
    public func getTopic(topicName: String) -> TopicProto? {
        if topicName.isEmpty {
            return nil
        }
        return topics[topicName]
    }

    public static func topicTypeByName(name: String?) -> TopicType {
        var r: TopicType = .unknown
        if let name = name, !name.isEmpty {
            switch name {
            case kTopicMe:
                r = .me
            case kTopicFnd:
                r = .fnd
            default:
                if name.starts(with: kTopicGrpPrefix) || name.starts(with: kTopicNew) {
                    r = .grp
                } else if name.starts(with: kTopicUsrPrefix) {
                    r = .p2p
                }
            }
        }
        return r
    }

    /// Create account using a single basic authentication scheme. A connection must be established
    /// prior to calling this method.
    ///
    /// - Parameters:
    ///   - uname: user name
    ///   - pwd: password
    ///   - login: use the new account for authentication
    ///   - tags: discovery tags
    ///   - desc: account parameters, such as full name etc.
    ///   - creds:  account credential, such as email or phone
    /// - Returns: PromisedReply of the reply ctrl message
    public func createAccountBasic<Pu: Codable, Pr: Codable>(
        uname: String,
        pwd: String,
        login: Bool,
        tags: [String]?,
        desc: MetaSetDesc<Pu, Pr>,
        creds: [Credential]?) -> PromisedReply<ServerMessage>? {
        guard let encodedSecret = try? AuthScheme.encodeBasicToken(uname: uname, password: pwd) else {
            return nil
        }
        return account(
            uid: Tinode.kUserNew,
            scheme: AuthScheme.kLoginBasic,
            secret: encodedSecret,
            loginNow: login,
            tags: tags,
            desc: desc,
            creds: creds)
    }

    /// Create new account. Connection must be established prior to calling this method.
    ///
    /// - Parameters:
    ///   - uid: uid of the user to affect
    ///   - scheme: authentication scheme to use
    ///   - secret: authentication secret for the chosen scheme
    ///   - loginNow: use new account to login immediately
    ///   - tags: tags
    ///   - desc: default access parameters for this account
    ///   - creds: creds
    /// - Returns: PromisedReply of the reply ctrl message
    public func account<Pu: Codable, Pr: Codable>(
        uid: String?,
        scheme: String,
        secret: String,
        loginNow: Bool,
        tags: [String]?,
        desc: MetaSetDesc<Pu, Pr>?,
        creds: [Credential]?) -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msga = MsgClientAcc(id: msgId, uid: uid, scheme: scheme, secret: secret, doLogin: loginNow, desc: desc)

        if let creds = creds, creds.count > 0 {
            for c in creds {
                msga.addCred(cred: c)
            }
        }

        if let tags = tags, tags.count > 0 {
            for t in tags {
                msga.addTag(tag: t)
            }
        }

        let msg = ClientMessage<Pu,Pr>(acc: msga)
        let future = sendWithPromise(payload: msg, with: msgId)

        if !loginNow {
            return future
        }
        return try! future.then(
            onSuccess: { [weak self] pkt in
                try self?.loginSuccessful(ctrl: pkt?.ctrl)
                return nil
            }, onFailure: { [weak self] err in
                if let e = err as? TinodeError {
                    if case TinodeError.serverResponseError(let code, let text, _) = e {
                        if code >= 400 && code < 500 {
                            // todo:
                            // clear auth data.
                        }
                        self?.isConnectionAuthenticated = false
                        self?.listenerNotifier.onLogin(code: code, text: text)
                    }
                }
                return PromisedReply<ServerMessage>(error: err)
            })
    }
    private func setAutoLogin(using scheme: String?,
                              authenticateWith secret: String?) {
        guard let scheme = scheme, let secret = secret else {
            autoLogin = false
            loginCredentials = nil
            return
        }
        autoLogin = true
        loginCredentials = LoginCredentials(using: scheme, authenticateWith: secret)
    }
    public func setAutoLoginWithToken(token: String) {
        setAutoLogin(using: AuthScheme.kLoginToken, authenticateWith: token)
    }
    public func loginBasic(uname: String, password: String) -> PromisedReply<ServerMessage>? {
        var encodedToken: String
        do {
            encodedToken = try AuthScheme.encodeBasicToken(
                uname: uname, password: password)
        } catch {
            Tinode.log.error("Won't login - failed encoding token: %@", error.localizedDescription)
            return nil
        }
        return login(scheme: AuthScheme.kLoginBasic,
                     secret: encodedToken,
                     creds: nil)
    }

    public func loginToken(token: String, creds: [Credential]?) -> PromisedReply<ServerMessage>? {
        return login(scheme: AuthScheme.kLoginToken, secret: token, creds: creds)
    }

    public func login(scheme: String, secret: String, creds: [Credential]?) -> PromisedReply<ServerMessage>? {
        if autoLogin {
            loginCredentials = LoginCredentials(using: scheme, authenticateWith: secret)
        }
        guard !isConnectionAuthenticated else {
            // Already logged in.
            return PromisedReply<ServerMessage>(value: ServerMessage())
        }
        guard !loginInProgress else {
            return PromisedReply<ServerMessage>(error: TinodeError.invalidState("Login in progress"))
        }
        loginInProgress = true
        let msgId = getNextMsgId()
        let msgl = MsgClientLogin(id: msgId, scheme: scheme, secret: secret, credentials: nil)
        if let creds = creds, creds.count > 0 {
            for c in creds {
                msgl.addCred(c: c)
            }
        }
        let msg = ClientMessage<Int, Int>(login: msgl)
        return try! sendWithPromise(payload: msg, with: msgId).then(
            onSuccess: { [weak self] pkt in
                self?.loginInProgress = false
                try self?.loginSuccessful(ctrl: pkt?.ctrl)
                return nil
            },
            onFailure: { [weak self] err in
                self?.loginInProgress = false
                if let e = err as? TinodeError {
                    if case TinodeError.serverResponseError(let code, let text, _) = e {
                        if code >= 400 && code < 500 {
                            // todo:
                            // clear auth data.
                            self?.loginCredentials = nil
                            self?.authToken = nil
                        }
                        self?.isConnectionAuthenticated = false
                        self?.listenerNotifier.onLogin(code: code, text: text)
                    }
                }
                return PromisedReply<ServerMessage>(error: err)
            })
    }

    private func loginSuccessful(ctrl: MsgServerCtrl?) throws {
        guard let ctrl = ctrl else {
            throw TinodeError.invalidReply("Unexpected type of server response")
        }
        let newUid = ctrl.getStringParam(for: "user")
        if let curUid = myUid, curUid != newUid {
            logout()
            listenerNotifier.onLogin(code: 400, text: "UID mismatch")
            return
        }
        myUid = newUid
        authToken = ctrl.getStringParam(for: "token")
        // auth expires
        if ctrl.code < 300 {
            store?.myUid = newUid
            // Load topics if not yet loaded.
            loadTopics()
        } else {
            let meth = ctrl.getStringArray(for: "cred")
            store?.setMyUid(uid: newUid!, credMethods: meth)
        }
        isConnectionAuthenticated = 200...299 ~= ctrl.code
        listenerNotifier.onLogin(code: ctrl.code, text: ctrl.text)
    }
    private func updateAccountSecret(uid: String?, scheme: String, secret: String) -> PromisedReply<ServerMessage>? {
        return account(uid: uid, scheme: scheme, secret: secret, loginNow: false, tags: nil, desc: nil as MetaSetDesc<Int, Int>?, creds: nil)
    }
    @discardableResult
    public func updateAccountBasic(uid: String?, username: String, password: String) -> PromisedReply<ServerMessage>? {
        do {
            return try updateAccountSecret(
                uid: uid, scheme: AuthScheme.kLoginBasic,
                secret: AuthScheme.encodeBasicToken(uname: username, password: password))
        } catch {
            return nil
        }
    }
    public func requestResetPassword(method: String, newValue: String) -> PromisedReply<ServerMessage>? {
        do {
            return try login(scheme: AuthScheme.kLoginReset, secret: AuthScheme.encodeResetToken(scheme: AuthScheme.kLoginBasic, method: method, value: newValue), creds: nil)
        } catch {
            return nil
        }
    }
    public func disconnect() {
        // Remove auto-login data.
        setAutoLogin(using: nil, authenticateWith: nil)
        connection?.disconnect()
    }
    public func logout() {
        try? setDeviceToken(token: Tinode.kNullValue)?.thenFinally {
            self.disconnect()
            self.myUid = nil
            self.store?.logout()
        }
    }
    private func handleDisconnect(isServerOriginated: Bool, code: Int, reason: String) {
        let e = TinodeError.notConnected("no longer connected to server")
        futures.rejectAndPurgeAll(withError: e)
        serverBuild = nil
        serverVersion = nil
        isConnectionAuthenticated = false
        for t in topics.values {
            t.topicLeft(unsub: false, code: 503, reason: "disconnected")
        }
        listenerNotifier.onDisconnect(byServer: isServerOriginated, code: code, reason: reason)
    }
    public class TinodeConnectionListener : ConnectionListener {
        var tinode: Tinode
        init(tinode: Tinode) {
            self.tinode = tinode
        }
        func onConnect(reconnecting: Bool) -> Void {
            let m = reconnecting ? "YES" : "NO"
            Tinode.log.info("Tinode connected: after reconnect - %@", m.description)
            do {
                let future = try tinode.hello()?.then(onSuccess: { [weak self] pkt in
                    guard self != nil else {
                        throw TinodeError.invalidState("Missing Tinode instance in connection handler")
                    }
                    let tinode = self!.tinode
                    if let connected = tinode.connectedPromise, !connected.isDone {
                        try connected.resolve(result: pkt)
                    }
                    if let ctrl = pkt?.ctrl {
                        tinode.timeAdjustment = Date().timeIntervalSince(ctrl.ts)
                        // tinode store
                        tinode.store?.setTimeAdjustment(adjustment: tinode.timeAdjustment)
                        // listener
                        tinode.listenerNotifier.onConnect(code: ctrl.code, reason: ctrl.text, params: ctrl.params)
                    }
                    return nil
                }, onFailure: nil)
                if tinode.autoLogin && reconnecting {
                    try future?.then(
                        onSuccess: { [weak self] msg in
                            if let t = self?.tinode, let cred = t.loginCredentials, !t.loginInProgress {
                                _ = self?.tinode.login(
                                    scheme: cred.scheme, secret: cred.secret, creds: nil)
                            }
                            return nil
                        },
                        onFailure: nil)
                }
            } catch {
                Tinode.log.error("Connection error: %@", error.localizedDescription)
            }
        }
        func onMessage(with message: String) -> Void {
            Log.default.debug("in: %@", message)
            do {
                try tinode.dispatch(message)
            } catch {
                Log.default.error("onMessage error: %@", error.localizedDescription)
            }
        }
        func onDisconnect(isServerOriginated: Bool, code: Int, reason: String) -> Void {
            tinode.handleDisconnect(isServerOriginated: isServerOriginated, code: code, reason: reason)
        }
        func onError(error: Error) -> Void {
            tinode.handleDisconnect(isServerOriginated: true, code: 0, reason: error.localizedDescription)
            Log.default.error("Tinode network error: %@", error.localizedDescription)
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
            Tinode.log.debug("Tinode is already connected")
            return PromisedReply<ServerMessage>(value: ServerMessage())
        }
        self.useTLS = useTLS
        self.hostName = hostName
        guard let endpointURL = self.channelsURL(useWebsocketProtocol: true) else {
            throw TinodeError.invalidState("Could not form server url.")
        }
        connection = Connection(open: endpointURL,
                                with: apiKey,
                                notify: TinodeConnectionListener(tinode: self))
        connectedPromise = PromisedReply<ServerMessage>()
        try connection?.connect()
        return connectedPromise
    }

    @discardableResult
    public func reconnectNow() -> Bool {
        guard connection != nil && !isConnected else { return false }
        do {
            try connection!.connect(reconnectAutomatically: true)
            return true
        } catch {
            return false
        }
    }

    /**
     * Set device token for push notifications.
     *
     * @param token device token
     */
    @discardableResult
    public func setDeviceToken(token: String) -> PromisedReply<ServerMessage>? {
        guard token != deviceToken else {
            return PromisedReply<ServerMessage>(value: ServerMessage())
        }
        // Cache token here assuming the call to server does not fail. If it fails clear the cached token.
        // This prevents multiple unnecessary calls to the server with the same token.
        deviceToken = Tinode.isNull(obj: token) ? nil : token
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(hi: MsgClientHi(id: msgId, dev: token))
        return try? sendWithPromise(payload: msg, with: msgId)
            .thenCatch(onFailure: { [weak self] err in
                // Clear cached value on failure to allow for retries.
                self?.deviceToken = nil
                self?.store?.deviceToken = nil
                return nil
            })
    }

    public func subscribe<Pu: Codable, Pr: Codable>(
        to topicName: String,
        set: MsgSetMeta<Pu, Pr>?,
        get: MsgGetMeta?) -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Pu, Pr>(
            sub: MsgClientSub(
                id: msgId,
                topic: topicName,
                set: set,
                get: get))
        return sendWithPromise(payload: msg, with: msgId)
    }

    public func getMeta(topic: String, query: MsgGetMeta) -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(  // generic params don't matter
            get: MsgClientGet(
                id: msgId,
                topic: topic,
                query: query))
        return sendWithPromise(payload: msg, with: msgId)
    }
    public func setMeta<Pu: Codable, Pr: Codable>(
        for topic: String, meta: MsgSetMeta<Pu, Pr>?) -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msg = ClientMessage(
            set: MsgClientSet(id: msgId, topic: topic, meta: meta)
        )
        return sendWithPromise(payload: msg, with: msgId)
    }
    public func leave(topic: String, unsub: Bool?) -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(
            leave: MsgClientLeave(id: msgId, topic: topic, unsub: unsub))
        return sendWithPromise(payload: msg, with: msgId)
    }

    internal func publish(topic: String, head: [String:JSONValue]?, content: Drafty) -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(
            pub: MsgClientPub(id: msgId, topic: topic, noecho: true, head: head, content: content))
        return sendWithPromise(payload: msg, with: msgId)
    }

    public func publish(topic: String, data: Drafty) -> PromisedReply<ServerMessage>? {
        return publish(topic: topic,
                       head: data.isPlain ? nil : ["mime": JSONValue.string(Drafty.kMimeType)],
                       content: data)
    }
    public func getTopics() -> Array<TopicProto>? {
        return Array(topics.values)
    }
    public func getFilteredTopics(filter: ((TopicProto) -> Bool)?) -> Array<TopicProto>? {
        var result: Array<TopicProto>
        if filter == nil {
            result = topics.values.compactMap { $0 }
        } else {
            result = topics.values.filter { (topic) -> Bool in
                return filter!(topic)
            }
        }
        result.sort(by: { ($0.touched ?? Date.distantPast) > ($1.touched ?? Date.distantPast) })
        return result
    }

    private func sendDeleteMessage(msg: ClientMessage<Int, Int>) -> PromisedReply<ServerMessage>? {
        guard let msgId = msg.del?.id else { return nil }
        return sendWithPromise(payload: msg, with: msgId)
    }
    func delMessage(topicName: String?, fromId: Int, toId: Int, hard: Bool) -> PromisedReply<ServerMessage>? {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(),
                                  topic: topicName,
                                  from: fromId, to: toId, hard: hard)))
    }
    func delMessage(topicName: String?, list: [Int]?, hard: Bool) -> PromisedReply<ServerMessage>? {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(),
                                  topic: topicName, list: list, hard: hard)))
    }
    func delMessage(topicName: String?, msgId: Int, hard: Bool) -> PromisedReply<ServerMessage>? {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(),
                                  topic: topicName, msgId: msgId, hard: hard)))
    }
    func delSubscription(topicName: String?, user: String?) -> PromisedReply<ServerMessage>? {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(),
                                  topic: topicName, user: user)))
    }

    /// Low-level request to delete topic. Use {@link Topic#delete()} instead.
    ///
    /// - Parameters:
    ///   - topicName: name of the topic to delete
    /// - Returns: PromisedReply of the reply ctrl message
    func delTopic(topicName: String?) -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(del: MsgClientDel(id: msgId, topic: topicName))
        return sendWithPromise(payload: msg, with: msgId)
    }

    static func serializeObject<T: Encodable>(_ t: T) -> String? {
        guard let jsonData = try? Tinode.jsonEncoder.encode(t) else {
            return nil
        }
        let typeName = String(describing: T.self)
        let json = String(decoding: jsonData, as: UTF8.self)
        return [typeName, json].joined(separator: ";")
    }
    static func deserializeObject<T: Decodable>(from data: String?) -> T? {
        guard let parts = data?.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true), parts.count == 2 else {
            return nil
        }
        guard parts[0] == String(describing: T.self), let d = String(parts[1]).data(using: .utf8) else {
            return nil
        }
        return try? Tinode.jsonDecoder.decode(T.self, from: d)
    }

    public static func isNull(obj: Any?) -> Bool {
        guard let obj = obj as? String else { return false }
        return obj == Tinode.kNullValue
    }
}
