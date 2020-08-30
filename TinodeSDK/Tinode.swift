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
    case invalidArgument(String)
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
            case .invalidArgument(let message):
                return "Invalid argument: \(message)"
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
    public static let kChannelNew = "nch"
    public static let kTopicMe = "me"
    public static let kTopicFnd = "fnd"
    public static let kTopicSys = "sys"

    public static let kTopicGrpPrefix = "grp"
    public static let kTopicUsrPrefix = "usr"
    public static let kTopicChnPrefix = "chn"

    // Keys for server-provided limits.
    public static let kMaxMessageSize = "maxMessageSize"
    public static let kMaxSubscriberCount = "maxSubscriberCount"
    public static let kMaxTagCount = "maxTagCount"
    public static let kMaxFileUploadSize = "maxFileUploadSize"

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
        private let futuresQueue = DispatchQueue(label: "co.tinode.futuresmap")
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
            futuresQueue.sync {
                let expirationThreshold = Date().addingTimeInterval(TimeInterval(-ConcurrentFuturesMap.kFutureTimeout))
                let error = TinodeError.serverResponseError(ServerMessage.kStatusGatewayTimeout, "timeout", nil)
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
            get { return futuresQueue.sync { return futuresDict[key] } }
            set { futuresQueue.sync { futuresDict[key] = newValue } }
        }
        func removeValue(forKey key: String) -> PromisedReply<ServerMessage>? {
            return futuresQueue.sync { return futuresDict.removeValue(forKey: key) }
        }
        func rejectAndPurgeAll(withError e: Error) {
            futuresQueue.sync {
                for f in futuresDict.values {
                    try? f.reject(error: e)
                }
                futuresDict.removeAll()
            }
        }
    }

    // A simple thread-safe wrapper around Dictionary<String, T>.
    private class ConcurrentMap<T> {
        private var internalMap = [String:T]()
        private let opsQueue = DispatchQueue(label: "co.tinode.map-ops")

        var values: Dictionary<String, T>.Values {
            opsQueue.sync { return internalMap.values }
        }
        var count: Int {
            opsQueue.sync { return internalMap.count }
        }

        subscript(key: String) -> T? {
            get { return opsQueue.sync { return internalMap[key] } }
            set { opsQueue.sync { internalMap[key] = newValue } }
        }
        func removeValue(forKey key: String) -> T? {
            return opsQueue.sync { return internalMap.removeValue(forKey: key) }
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
    private var serverLimits: [String:Int64]?
    private var connectionListener: TinodeConnectionListener? = nil
    public var timeAdjustment: TimeInterval = 0
    public var isConnectionAuthenticated = false
    public var myUid: String?
    public var deviceToken: String?
    public var authToken: String?
    public var authTokenExpires: Date?
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
    // Queue to execute state-mutating operations on.
    private let operationsQueue = DispatchQueue(label: "co.tinode.operations")

    public func hostURL(useWebsocketProtocol: Bool) -> URL? {
        guard !hostName.isEmpty else { return nil }
        let protocolString = useTLS ? (useWebsocketProtocol ? "wss://" : "https://") : (useWebsocketProtocol ? "ws://" : "http://")
        let urlString = "\(protocolString)\(hostName)/"
        return URL(string: urlString)
    }
    public func baseURL(useWebsocketProtocol: Bool) -> URL? {
        return hostURL(useWebsocketProtocol: useWebsocketProtocol)?.appendingPathComponent("v\(kProtocolVersion)")
    }
    public func channelsURL(useWebsocketProtocol: Bool) -> URL? {
        return baseURL(useWebsocketProtocol: useWebsocketProtocol)?.appendingPathComponent("/channels")
    }
    public var isConnected: Bool {
        if let c = connection, c.isConnected {
            return true
        }
        return false
    }

    private var topics = ConcurrentMap<TopicProto>()
    private var users = ConcurrentMap<UserProto>()

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
                if let updated = t.updated, topicsUpdated ?? Date.distantPast < updated {
                    topicsUpdated = updated
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
        return "\(appName) (iOS \(OsVersion); \(kLocale)); tinode-swift/\(kLibVersion)"
    }

    public func getServerLimit(for key: String, withDefault defVal: Int64) -> Int64 {
        return self.serverLimits?[key] ?? defVal
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
                    if ServerMessage.kStatusOk <= ctrl.code && ctrl.code < ServerMessage.kStatusBadRequest {
                        try r.resolve(result: serverMsg)
                    } else {
                        try r.reject(error: TinodeError.serverResponseError(ctrl.code, ctrl.text, ctrl.getStringParam(for: "what")))
                    }
                }
            }
            if ctrl.code == ServerMessage.kStatusResetContent && ctrl.text == "evicted" {
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
                    // For P2P topics presence is addressed to 'me' only. Forward it to the actual topic, if it's found.
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

    private func sendWithPromise<DP: Codable, DR: Codable>(payload msg: ClientMessage<DP,DR>, with id: String) -> PromisedReply<ServerMessage> {
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

    private func hello(inBackground bkg: Bool) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(hi: MsgClientHi(id: msgId, ver: kVersion, ua: userAgent, dev: deviceToken, lang: kLocale, background: bkg))
        return sendWithPromise(payload: msg, with: msgId)
            .thenApply({ [weak self] pkt in
                guard let ctrl = pkt?.ctrl else {
                    throw TinodeError.invalidReply("Unexpected type of reply packet to hello")
                }
                guard let tn = self else { return nil }
                if !(ctrl.params?.isEmpty ?? true) {
                    tn.serverVersion = ctrl.getStringParam(for: "ver")
                    tn.serverBuild = ctrl.getStringParam(for: "build")
                    tn.serverLimits = [:]
                    for k in [Tinode.kMaxMessageSize, Tinode.kMaxSubscriberCount, Tinode.kMaxTagCount, Tinode.kMaxFileUploadSize] {
                        if let v = ctrl.getInt64Param(for: k) {
                            tn.serverLimits![k] = v
                        } else {
                            Tinode.log.error("Server limit missing for key %@", k)
                        }
                    }
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
        _ = topics.removeValue(forKey: topicName)
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
    public static func newTopic(withTinode tinode: Tinode?, forTopic name: String) -> TopicProto {
        if name == Tinode.kTopicMe {
            return DefaultMeTopic(tinode: tinode)
        }
        if name == Tinode.kTopicFnd {
            return DefaultFndTopic(tinode: tinode)
        }
        return DefaultComTopic(tinode: tinode, name: name, l: nil)
    }
    public func newTopic(for name: String) -> TopicProto {
        return Tinode.newTopic(withTinode: self, forTopic: name)
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
                if name.starts(with: kTopicGrpPrefix) || name.starts(with: kTopicNew) || name.starts(with: kTopicChnPrefix) || name.starts(with: kChannelNew) {
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
        creds: [Credential]?) -> PromisedReply<ServerMessage> {
        let encodedSecret: String
        do {
            encodedSecret = try AuthScheme.encodeBasicToken(uname: uname, password: pwd)
        } catch {
            return PromisedReply(error: TinodeError.invalidArgument(error.localizedDescription))
        }
        return account(uid: Tinode.kUserNew,
            scheme: AuthScheme.kLoginBasic,
            secret: encodedSecret,
            loginNow: login,
            tags: tags,
            desc: desc,
            creds: creds)
    }

    private func handleAuthenticationError(error: Error) {
        if let e = error as? TinodeError {
            if case TinodeError.serverResponseError(let code, let text, _) = e {
                if ServerMessage.kStatusBadRequest <= code && code < ServerMessage.kStatusInternalServerError {
                    // clear auth data.
                    self.loginCredentials = nil
                    self.authToken = nil
                    self.authTokenExpires = nil
                }
                self.isConnectionAuthenticated = false
                self.listenerNotifier.onLogin(code: code, text: text)
            }
        }
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
        creds: [Credential]?) -> PromisedReply<ServerMessage> {
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
        return future.then(
            onSuccess: { [weak self] pkt in
                try self?.loginSuccessful(ctrl: pkt?.ctrl)
                return nil
            },
            onFailure: { [weak self] err in
                self?.handleAuthenticationError(error: err)
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
    public func loginBasic(uname: String, password: String) -> PromisedReply<ServerMessage> {
        var encodedToken: String
        do {
            encodedToken = try AuthScheme.encodeBasicToken(uname: uname, password: password)
        } catch {
            Tinode.log.error("Won't login - failed encoding token: %@", error.localizedDescription)
            return PromisedReply(error: error)
        }
        return login(scheme: AuthScheme.kLoginBasic, secret: encodedToken, creds: nil)
    }

    public func loginToken(token: String, creds: [Credential]?) -> PromisedReply<ServerMessage> {
        return login(scheme: AuthScheme.kLoginToken, secret: token, creds: creds)
    }

    public func login(scheme: String, secret: String, creds: [Credential]?) -> PromisedReply<ServerMessage> {
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
        return sendWithPromise(payload: msg, with: msgId).then(
            onSuccess: { [weak self] pkt in
                self?.loginInProgress = false
                try self?.loginSuccessful(ctrl: pkt?.ctrl)
                return nil
            },
            onFailure: { [weak self] err in
                self?.loginInProgress = false
                self?.handleAuthenticationError(error: err)
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
            listenerNotifier.onLogin(code: ServerMessage.kStatusBadRequest, text: "UID mismatch")
            throw TinodeError.invalidState(
                "UID mismatch: received '\(newUid ?? "")', expected '\(curUid)'")
        }
        myUid = newUid

        authToken = ctrl.getStringParam(for: "token")
        authTokenExpires = authToken != nil ?
            Formatter.rfc3339.date(from: ctrl.getStringParam(for: "expires") ?? "") : nil

        // auth expires
        if ctrl.code < ServerMessage.kStatusMultipleChoices {
            isConnectionAuthenticated = true
            store?.myUid = newUid
            setAutoLoginWithToken(token: authToken!)
            // Load topics if not yet loaded.
            loadTopics()
            listenerNotifier.onLogin(code: ctrl.code, text: ctrl.text)
        } else {
            isConnectionAuthenticated = false
            if let meth = ctrl.getStringArray(for: "cred") {
                store?.setMyUid(uid: newUid!, credMethods: meth)
            }
        }
    }
    private func updateAccountSecret(uid: String?, scheme: String, secret: String) -> PromisedReply<ServerMessage> {
        return account(uid: uid, scheme: scheme, secret: secret, loginNow: false, tags: nil, desc: nil as MetaSetDesc<Int, Int>?, creds: nil)
    }
    @discardableResult
    public func updateAccountBasic(uid: String?, username: String, password: String) -> PromisedReply<ServerMessage> {
        do {
            return try updateAccountSecret(uid: uid, scheme: AuthScheme.kLoginBasic,
                secret: AuthScheme.encodeBasicToken(uname: username, password: password))
        } catch {
            return PromisedReply(error: error)
        }
    }
    public func requestResetPassword(method: String, newValue: String) -> PromisedReply<ServerMessage> {
        do {
            return try login(scheme: AuthScheme.kLoginReset, secret: AuthScheme.encodeResetToken(scheme: AuthScheme.kLoginBasic, method: method, value: newValue), creds: nil)
        } catch {
            return PromisedReply(error: error)
        }
    }
    public func disconnect() {
        operationsQueue.sync {
            // Remove auto-login data.
            setAutoLogin(using: nil, authenticateWith: nil)
            connection?.disconnect()
        }
    }
    public func logout() {
        // setDeviceToken is thread-safe.
        setDeviceToken(token: Tinode.kNullValue).thenFinally {
            self.disconnect()
            self.myUid = nil
            self.serverLimits = nil
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
            t.topicLeft(unsub: false, code: ServerMessage.kStatusServiceUnavailable, reason: "disconnected")
        }
        listenerNotifier.onDisconnect(byServer: isServerOriginated, code: code, reason: reason)
    }
    public class TinodeConnectionListener : ConnectionListener {
        var tinode: Tinode
        var completionPromises : [PromisedReply<ServerMessage>] = []
        var promiseQueue = DispatchQueue(label: "co.tinode.completion-promises")

        init(tinode: Tinode) {
            self.tinode = tinode
        }
        func onConnect(reconnecting: Bool, param: Any?) -> Void {
            let m = reconnecting ? "YES" : "NO"
            Tinode.log.info("Tinode connected: after reconnect - %@", m.description)
            let doLogin = tinode.autoLogin && tinode.loginCredentials != nil
            var future = tinode.hello(inBackground: param as? Bool ?? false).thenApply({ [weak self] pkt in
                guard let self = self else {
                    throw TinodeError.invalidState("Missing Tinode instance in connection handler")
                }
                let tinode = self.tinode

                if let ctrl = pkt?.ctrl {
                    tinode.timeAdjustment = Date().timeIntervalSince(ctrl.ts)
                    // tinode store
                    tinode.store?.setTimeAdjustment(adjustment: tinode.timeAdjustment)
                    // listener
                    tinode.listenerNotifier.onConnect(code: ctrl.code, reason: ctrl.text, params: ctrl.params)
                }
                if !doLogin {
                    try self.resolveAllPromises(msg: pkt)
                }
                return nil
            })
            if doLogin {
                future = future.thenApply({ [weak self] msg in
                    if let t = self?.tinode, let cred = t.loginCredentials, !t.loginInProgress {
                        return t.login(
                            scheme: cred.scheme, secret: cred.secret, creds: nil).then(
                                onSuccess: { msg in
                                    try self?.resolveAllPromises(msg: msg)
                                    return nil
                                },
                                onFailure: { err in
                                    Tinode.log.error("Login error: %@", err.localizedDescription)
                                    return PromisedReply<ServerMessage>(error: err)
                                })
                    }
                    return nil
                })
            }
            future.thenCatch({ err in
                Tinode.log.error("Connection error: %@", err.localizedDescription)
                return PromisedReply<ServerMessage>(error: err)
            })
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
            let serverOriginatedString = isServerOriginated ? "YES" : "NO"
            Log.default.info("Tinode disconnected: server originated [%@]; code [%d]; reason [%@]",
                             serverOriginatedString, code, reason)
            tinode.handleDisconnect(isServerOriginated: isServerOriginated, code: code, reason: reason)
        }
        func onError(error: Error) -> Void {
            tinode.handleDisconnect(isServerOriginated: true, code: 0, reason: error.localizedDescription)
            Log.default.error("Tinode network error: %@", error.localizedDescription)
            try? rejectAllPromises(err: error)
        }
        public func addPromise(promise: PromisedReply<ServerMessage>) {
            promiseQueue.sync {
                completionPromises.append(promise)
            }
        }
        private func completeAllPromises(msg: ServerMessage?, err: Error?) throws {
            let promises: [PromisedReply<ServerMessage>] = promiseQueue.sync {
                let promises = completionPromises.map { $0 }
                completionPromises.removeAll()
                return promises
            }
            if let e = err {
                try promises.forEach { try $0.reject(error: e) }
                return
            }
            if let msg = msg {
                try promises.forEach { try $0.resolve(result: msg) }
            }
        }
        private func resolveAllPromises(msg: ServerMessage?) throws {
            try completeAllPromises(msg: msg, err: nil)
        }
        private func rejectAllPromises(err: Error?) throws {
            try completeAllPromises(msg: nil, err: err)
        }
    }

    private func resetMsgId() {
        nextMsgId = 0xffff + Int((Float(arc4random()) / Float(UInt32.max)) * 0xffff)
    }

    @discardableResult
    public func connect(to hostName: String, useTLS: Bool, inBackground bkg: Bool) throws -> PromisedReply<ServerMessage>? {
        try operationsQueue.sync {
            return try connectThreadUnsafe(to: hostName, useTLS: useTLS, inBackground: bkg)
        }
    }

    private func connectThreadUnsafe(to hostName: String, useTLS: Bool, inBackground bkg: Bool) throws -> PromisedReply<ServerMessage>? {
        if isConnected {
            Tinode.log.debug("Tinode is already connected")
            return PromisedReply<ServerMessage>(value: ServerMessage())
        }
        self.useTLS = useTLS
        self.hostName = hostName
        guard let endpointURL = self.channelsURL(useWebsocketProtocol: true) else {
            throw TinodeError.invalidState("Could not form server url.")
        }
        resetMsgId()
        if connection == nil {
            connectionListener = TinodeConnectionListener(tinode: self)
            connection = Connection(open: endpointURL,
                                    with: apiKey,
                                    notify: connectionListener)
        }
        let connectedPromise = PromisedReply<ServerMessage>()
        connectionListener!.addPromise(promise: connectedPromise)
        try connection!.connect(withParam: bkg)
        return connectedPromise
    }

    // Connect with saved connection params (host name and tls settings).
    @discardableResult
    private func connect(inBackground bkg: Bool) throws -> PromisedReply<ServerMessage>? {
        return try connectThreadUnsafe(to: self.hostName, useTLS: self.useTLS, inBackground: bkg)
    }

    // Make sure connection is either already established or being established:
    //  - If connection is already established do nothing
    //  - If connection does not exist, create
    //  - If not connected and waiting for backoff timer, wake it up.
    //
    // |interactively| is true if user directly requested a reconnect.
    // If |reset| is true, drop connection and reconnect. Happens when cluster is reconfigured.
    @discardableResult
    public func reconnectNow(interactively: Bool, reset: Bool) -> Bool {
        operationsQueue.sync {
            var reconnectInteractive = interactively
            if connection == nil {
                do {
                    try connect(inBackground: false)
                    return true
                } catch {
                    Tinode.log.error("Couldn't connect to server: %@", error.localizedDescription)
                    return false
                }
            }
            if connection!.isConnected {
                // We are done unless we need to reset the connection.
                if !reset {
                    return true
                }
                connection!.disconnect()
                reconnectInteractive = true
            }

            // Connection exists but not connected.
            // Try to connect immediately only if requested or if
            // autoreconnect is not enabled.
            if reconnectInteractive || !connection!.isWaitingToConnect {
                do {
                    try connection!.connect(reconnectAutomatically: true, withParam: nil)
                    return true
                } catch {
                    return false
                }
            }
            return false
        }
    }

    /**
     * Set device token for push notifications.
     *
     * @param token device token
     */
    @discardableResult
    public func setDeviceToken(token: String) -> PromisedReply<ServerMessage> {
        operationsQueue.sync {
            guard token != deviceToken else {
                return PromisedReply<ServerMessage>(value: ServerMessage())
            }
            // Cache token here assuming the call to server does not fail. If it fails clear the cached token.
            // This prevents multiple unnecessary calls to the server with the same token.
            deviceToken = Tinode.isNull(obj: token) ? nil : token
            let msgId = getNextMsgId()
            let msg = ClientMessage<Int, Int>(hi: MsgClientHi(id: msgId, dev: token))
            return sendWithPromise(payload: msg, with: msgId)
                .thenCatch { [weak self] err in
                    // Clear cached value on failure to allow for retries.
                    self?.deviceToken = nil
                    self?.store?.deviceToken = nil
                    return nil
                }
        }
    }

    public func subscribe<Pu: Codable, Pr: Codable>(to topicName: String, set: MsgSetMeta<Pu, Pr>?, get: MsgGetMeta?) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Pu, Pr>(
            sub: MsgClientSub(
                id: msgId,
                topic: topicName,
                set: set,
                get: get))
        return sendWithPromise(payload: msg, with: msgId)
    }

    public func getMeta(topic: String, query: MsgGetMeta) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(  // generic params don't matter
            get: MsgClientGet(
                id: msgId,
                topic: topic,
                query: query))
        return sendWithPromise(payload: msg, with: msgId)
    }

    public func setMeta<Pu: Codable, Pr: Codable>(for topic: String, meta: MsgSetMeta<Pu, Pr>?) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage(
            set: MsgClientSet(id: msgId, topic: topic, meta: meta)
        )
        return sendWithPromise(payload: msg, with: msgId)
    }

    public func leave(topic: String, unsub: Bool?) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(
            leave: MsgClientLeave(id: msgId, topic: topic, unsub: unsub))
        return sendWithPromise(payload: msg, with: msgId)
    }

    public static func draftyHeaders(for message: Drafty) -> [String: JSONValue]? {
        guard !message.isPlain else { return nil }
        var head: [String: JSONValue] = [:]
        head["mime"] = JSONValue.string(Drafty.kMimeType)
        if let refs = message.getEntReferences() {
            head["attachments"] = JSONValue.array(refs.map { JSONValue.string($0) })
        }
        return head
    }

    public func publish(topic: String, head: [String:JSONValue]?, content: Drafty) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(
            pub: MsgClientPub(id: msgId, topic: topic, noecho: true, head: head, content: content))
        return sendWithPromise(payload: msg, with: msgId)
    }

    public func getTopics() -> Array<TopicProto>? {
        return Array(topics.values)
    }
    public func getFilteredTopics(filter: ((TopicProto) -> Bool)?) -> Array<TopicProto>? {
        guard let filter = filter else {
            return topics.values.compactMap { $0 }
        }

        var result = topics.values.filter { (topic) -> Bool in
            return filter(topic)
        }
        result.sort(by: { ($0.touched ?? Date.distantPast) > ($1.touched ?? Date.distantPast) })
        return result
    }

    public func countFilteredTopics(filter: ((TopicProto) -> Bool)?) -> Int {
        guard let filter = filter else { return topics.count }

        var count = 0
        topics.values.forEach { topic in
            if filter(topic) {
                count += 1
            }
        }
        return count
    }

    private func sendDeleteMessage(msg: ClientMessage<Int, Int>) -> PromisedReply<ServerMessage> {
        return sendWithPromise(payload: msg, with: msg.del!.id!)
    }

    func delMessage(topicName: String, fromId: Int, toId: Int?, hard: Bool) -> PromisedReply<ServerMessage> {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(),
                                  topic: topicName,
                                  from: fromId, to: toId, hard: hard)))
    }
    func delMessage(topicName: String, ranges: [MsgRange]?, hard: Bool) -> PromisedReply<ServerMessage> {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(), topic: topicName, ranges: ranges, hard: hard)))
    }
    func delMessage(topicName: String, msgId: Int, hard: Bool) -> PromisedReply<ServerMessage> {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(), topic: topicName, msgId: msgId, hard: hard)))
    }
    func delSubscription(topicName: String, user: String?) -> PromisedReply<ServerMessage> {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(), topic: topicName, user: user)))
    }

    /// Low-level request to delete a credential. Use {@link MeTopic#delCredential(String, String)} ()} instead.
    ///
    /// - Parameters
    ///  - cred  credential to delete.
    /// - Returns: PromisedReply of the reply ctrl message
    func delCredential(cred: Credential) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(del: MsgClientDel(id: msgId, cred: cred))
        return sendWithPromise(payload: msg, with: msgId)
    }

    /// Request to delete account of the current user.
    /// - Parameters
    ///  - hard hard-delete user
    /// - Returns: PromisedReply of the reply ctrl message
    public func delCurrentUser(hard: Bool) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(del: MsgClientDel(id: msgId, hard: hard))
        return sendWithPromise(payload: msg, with: msgId).thenApply{ [weak self] _ in
            guard let this = self else { return nil }
            this.disconnect()
            this.store?.deleteAccount(this.myUid!)
            this.myUid = nil
            return nil
        }
    }

    /// Low-level request to delete topic. Use {@link Topic#delete()} instead.
    ///
    /// - Parameters:
    ///   - topicName: name of the topic to delete
    ///   - hard: hard-delete topic
    /// - Returns: PromisedReply of the reply ctrl message
    func delTopic(topicName: String, hard: Bool) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(del: MsgClientDel(id: msgId, topic: topicName, hard: hard))
        return sendWithPromise(payload: msg, with: msgId)
    }

    public static func serializeObject<T: Encodable>(_ t: T) -> String? {
        guard let jsonData = try? Tinode.jsonEncoder.encode(t) else {
            return nil
        }
        let typeName = String(describing: T.self)
        let json = String(decoding: jsonData, as: UTF8.self)
        return [typeName, json].joined(separator: ";")
    }
    public static func deserializeObject<T: Decodable>(from data: String?) -> T? {
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
