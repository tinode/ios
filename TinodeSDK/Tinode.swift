//
//  Tinode.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation


public enum TinodeJsonError: Error {
    case encode
    case decode
}

public enum TinodeError: Error, CustomStringConvertible {
    case invalidReply(String)
    case invalidState(String)
    case notConnected(String)
    case serverResponseError(Int, String, String?)
    case notSubscribed(String)

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
            }
        }
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
    public static let kTopicMe = "me"
    public static let kTopicFnd = "fnd"
    public static let kTopicGrpPrefix = "grp"
    public static let kTopicUsrPrefix = "usr"

    public static let kNoteKp = "kp"
    public static let kNoteRead = "read"
    public static let kNoteRecv = "recv"
    private static let log = Log(category: "co.tinode.tinodesdk")

    let kProtocolVersion = "0"
    let kVersion = "0.15"
    let kLibVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    let kLocale = Locale.current.languageCode!
    public var deviceId: String = ""
    public var OsVersion: String = ""

    public var appName: String
    public var apiKey: String
    public var connection: Connection?
    public var nextMsgId = 1
    public var futures: [String:PromisedReply<ServerMessage>] = [:]
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
    public var listener: TinodeEventListener? = nil
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

    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .customRFC3339
        return encoder
    }()
    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .customRFC3339
        return decoder
    }()

    public init(for appname: String, authenticateWith apiKey: String,
         persistDataIn store: Storage? = nil,
         fowardEventsTo l: TinodeEventListener? = nil) {
        self.appName = appname
        self.apiKey = apiKey
        self.store = store
        self.listener = l
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

    public func updateUser<DP: Codable, DR: Codable>(uid: String, desc: Description<DP, DR>) {
        if let user = users[uid] {
            _ = (user as? User<DP>)?.merge(from: desc)
        } else {
            let user = User<DP>(uid: uid, desc: desc)
            users[uid] = user
        }
        // store?.userUpdate(user)
    }
    public func updateUser<DP: Codable, DR: Codable>(sub: Subscription<DP, DR>) {
        let uid = sub.user!
        if let user = users[uid] {
            _ = (user as? User<DP>)?.merge(from: sub)
        } else {
            let user = try! User<DP>(sub: sub)
            users[uid] = user
        }
        // store?.userUpdate(user)
    }

    public func nextUniqueString() -> String {
        nameCounter += 1
        let millisecSince1970 = Int64(Date().timeIntervalSince1970 as Double * 1000)
        let q = ((millisecSince1970 - 1414213562373) << 16).advanced(by: nameCounter & 0xffff)
        return String(q, radix: 32)
    }

    private func getUserAgent() -> String {
        return "\(appName) (iOS \(OsVersion); \(kLocale)); tinode-swift/\(kLibVersion)"
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

        listener?.onRawMessage(msg: msg)
        guard let data = msg.data(using: .utf8) else {
            throw TinodeJsonError.decode
        }
        let serverMsg = try Tinode.jsonDecoder.decode(ServerMessage.self, from: data)

        listener?.onMessage(msg: serverMsg)

        if let ctrl = serverMsg.ctrl {
            listener?.onCtrlMessage(ctrl: ctrl)
            if let id = ctrl.id {
                if let r = futures.removeValue(forKey: id) {
                    if ctrl.code >= 200 && ctrl.code < 400 {
                        try r.resolve(result: serverMsg)
                    } else {
                        try r.reject(error: TinodeError.serverResponseError(
                            ctrl.code, ctrl.text, ctrl.getStringParam(for: "what")))
                    }
                }
                Tinode.log.debug("ctrl.id = %d", id)
            }
            if let what = ctrl.getStringParam(for: "what"), what == "data" {
                if let topic = ctrl.topic, let t = getTopic(topicName: topic) {
                    t.allMessagesReceived(count: ctrl.getIntParam(for: "count"))
                }
                Tinode.log.debug("what = %@", what)
            }
        } else if let meta = serverMsg.meta {
            var updated: Date? = nil
            if let t = getTopic(topicName: meta.topic!) {
                t.routeMeta(meta: meta)
                updated = t.updated
            } else if let t = maybeCreateTopic(meta: meta) {
                updated = t.updated
                Tinode.log.debug("created topic %@", meta.topic ?? "")
            }

            if let updated = updated {
                if topicsUpdated == nil || topicsUpdated! < updated {
                    topicsUpdated = updated
                }
            }

            listener?.onMetaMessage(meta: meta)
            try resolveWithPacket(id: meta.id, pkt: serverMsg)
            //if t != nil
        } else if let data = serverMsg.data {
            if let t = getTopic(topicName: data.topic!) {
                t.routeData(data: data)
            }
            listener?.onDataMessage(data: data)
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
            listener?.onPresMessage(pres: pres)
        } else if let info = serverMsg.info {
            if let topicName = info.topic {
                if let t = getTopic(topicName: topicName) {
                    t.routeInfo(info: info)
                }
                listener?.onInfoMessage(info: info)
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
        Tinode.log.debug("out: %{public}@", String(decoding: jsonData, as: UTF8.self))
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
                Tinode.log.error("Error rejecting promise: %{public}@", String(describing: error))
            }
        }
        return future
    }
    private func hello() -> PromisedReply<ServerMessage>? {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(
            hi: MsgClientHi(id: msgId, ver: kVersion,
                            ua: getUserAgent(), dev: deviceId,
                            lang: kLocale))
        return try! sendWithPromise(payload: msg, with: msgId).thenApply(
            onSuccess: { [weak self] pkt in
                guard let ctrl = pkt.ctrl else {
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
        //Topic topic = mTopics.remove(topicName);
        topics.removeValue(forKey: topicName)
    }

    /**
     * Check if topic is being tracked.
     */
    public func isTopicTracked(topicName: String) -> Bool {
        return topics[topicName] != nil
    }

    public func newTopic<SP: Codable, SR: Codable>(sub: Subscription<SP, SR>) -> TopicProto {
        if sub.topic == Tinode.kTopicMe {
            let t = MeTopic<SP>(tinode: self, l: nil)
            return t
        } else if sub.topic == Tinode.kTopicFnd {
            let r = FndTopic<SP>(tinode: self)
            return r
        }
        return ComTopic<SP>(tinode: self, sub: sub as! Subscription<SP, PrivateType>)
    }
    public func newTopic(for name: String, with listener: DefaultTopic.Listener?) -> TopicProto {
        if name == Tinode.kTopicMe {
            return DefaultMeTopic(tinode: self, l: listener)
        }
        if name == Tinode.kTopicFnd {
            return DefaultFndTopic(tinode: self)
        }
        return DefaultComTopic(tinode: self, name: name, l: listener)
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
                break
            default:
                if name.starts(with: kTopicGrpPrefix) || name.starts(with: kTopicNew) {
                    r = .grp
                } else if name.starts(with: kTopicUsrPrefix) {
                    r = .p2p
                }
                break
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
            uid: nil,
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
    ///   - loginNow: use new account to loin immediately
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
        desc: MetaSetDesc<Pu, Pr>,
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
                try self?.loginSuccessful(ctrl: pkt.ctrl)
                return nil
            }, onFailure: { [weak self] err in
                if let e = err as? TinodeError {
                    if case TinodeError.serverResponseError(let code, let text, _) = e {
                        if code >= 400 && code < 500 {
                            // todo:
                            // clear auth data.
                        }
                        self?.isConnectionAuthenticated = false
                        self?.listener?.onLogin(code: code, text: text)
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
            Tinode.log.error("Won't login - failed encoding token: %{public}@",
                             String(describing: error))
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
            return PromisedReply<ServerMessage>()
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
                try self?.loginSuccessful(ctrl: pkt.ctrl)
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
                        self?.listener?.onLogin(code: code, text: text)
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
            listener?.onLogin(code: 400, text: "UID mismatch")
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
            if let t = authToken, !autoLogin {
                setAutoLoginWithToken(token: t)
            }
            listener?.onLogin(code: ctrl.code, text: ctrl.text)
        }
    }
    public func disconnect() {
        // Remove auto-login data.
        setAutoLogin(using: nil, authenticateWith: nil)
        connection?.disconnect()
    }
    public func logout() {
        disconnect()
        myUid = nil
        store?.logout()
    }
    private func handleDisconnect(isServerOriginated: Bool, code: Int, reason: String) {
        let e = TinodeError.notConnected("no longer connected to server")
        for f in futures.values {
            try? f.reject(error: e)
        }
        futures.removeAll()
        serverBuild = nil
        serverVersion = nil
        isConnectionAuthenticated = false
        for t in topics.values {
            t.topicLeft(unsub: false, code: 503, reason: "disconnected")
        }
        listener?.onDisconnect(byServer: isServerOriginated, code: code, reason: reason)
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
                    let ctrl = pkt.ctrl!
                    tinode.timeAdjustment = Date().timeIntervalSince(ctrl.ts)
                    // tinode store
                    tinode.store?.setTimeAdjustment(adjustment: tinode.timeAdjustment)
                    // listener
                    tinode.listener?.onConnect(
                        code: ctrl.code, reason: ctrl.text, params: ctrl.params)
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
                Tinode.log.error("Connection error: %{public}@",
                                 String(describing: error))
            }
        }
        func onMessage(with message: String) -> Void {
            Log.debug("in: %{public}@", message)
            do {
                try tinode.dispatch(message)
            } catch {
                Log.error("onMessage error: %{public}@", String(describing: error))
            }
        }
        func onDisconnect(isServerOriginated: Bool, code: Int, reason: String) -> Void {
            tinode.handleDisconnect(isServerOriginated: isServerOriginated, code: code, reason: reason)
        }
        func onError(error: Error) -> Void {
            tinode.handleDisconnect(isServerOriginated: true, code: 0, reason: error.localizedDescription)
            Log.error("Tinode network error: %{public}@", String(describing: error))
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
            Tinode.log.error("Tinode is already connected")
            return nil
        }
        let urlString = "\(hostName)/v\(kProtocolVersion)/channels"
        let endpointURL: URL = URL(string: urlString)!
        connection = Connection(open: endpointURL,
                                with: apiKey,
                                notify: TinodeConnectionListener(tinode: self))
        connectedPromise = PromisedReply<ServerMessage>()
        try connection?.connect()
        return connectedPromise
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
    static func serializeObject<T: Encodable>(t: T) -> String? {
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
}
