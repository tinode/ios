//
//  ClientMessages.swift
//  ios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import Foundation

public class MsgClientHi: Codable {
    public let id: String?
    public let ver: String?
    // User Agent.
    public let ua: String?
    // Push notification token.
    public let dev: String?
    public let lang: String?
    public let bkg: Bool?

    init(id: String?, ver: String?, ua: String?, dev: String?, lang: String?, background: Bool) {
        self.id = id
        self.ver = ver
        self.ua = ua
        self.dev = dev
        self.lang = lang
        self.bkg = background ? true : nil
    }
    convenience init(id: String, dev: String) {
        self.init(id: id, ver: nil, ua: nil, dev: dev, lang: nil, background: false)
    }
}

public class Credential: Codable, Comparable, CustomStringConvertible {
    public static let kMethEmail = "email"
    public static let kMethPhone = "tel"
    // Confirmation method: email, phone, captcha.
    public var meth: String?
    // Credential to be confirmed, e.g. email or a phone number.
    public var val: String?
    // Confirmation response, such as '123456'.
    var resp: String?
    // Confirmation parameters.
    var params: [String: String]?
    // If credential is confirmed
    var done: Bool?

    public init(meth: String, val: String) {
        self.meth = meth
        self.val = val
    }

    public init(meth: String?, val: String?, resp: String?, params: [String: String]?) {
        self.meth = meth
        self.val = val
        self.resp = resp
        self.params = params
    }

    public var isDone: Bool {
        return done ?? false
    }

    public static func == (lhs: Credential, rhs: Credential) -> Bool {
        return lhs.meth == rhs.meth && lhs.val == rhs.val
    }

    public static func < (lhs: Credential, rhs: Credential) -> Bool {
        "\(lhs.meth ?? "-"):\(lhs.val ?? "-"):\(rhs.done ?? false)" < "\(rhs.meth ?? "-"):\(rhs.val ?? "-"):\(rhs.done ?? false)"
    }

    public var description: String {
        return "\(meth ?? "-"):\(val ?? "-")"
    }
}

public class MsgClientAcc<Pu: Codable, Pr: Codable>: Codable {
    var id: String?
    var user: String?
    var tmpscheme: String?
    var tmpsecret: String?
    var scheme: String?
    var secret: String?
    var login: Bool?
    var tags: [String]?
    var cred: [Credential]?
    var desc: MetaSetDesc<Pu, Pr>?

    init(id: String?,
         uid: String?,
         tmpscheme: String? = nil,
         tmpsecret: String? = nil,
         scheme: String?,
         secret: String?,
         doLogin: Bool,
         desc: MetaSetDesc<Pu, Pr>?) {
        self.id = id
        self.user = uid
        self.tmpscheme = tmpscheme
        self.tmpsecret = tmpsecret
        self.scheme = scheme
        self.login = doLogin
        self.desc = desc
        self.secret = secret
    }

    func addTag(tag: String) {
        if self.tags == nil {
            self.tags = [String]()
        }
        self.tags?.append(tag)
    }

    func addCred(cred: Credential) {
        if self.cred == nil {
            self.cred = [Credential]()
        }
        self.cred?.append(cred)
    }
}

public class MsgClientLogin: Codable {
    public let id: String?
    public let scheme: String?
    public let secret: String?
    public var cred: [Credential]?

    init(id: String?, scheme: String?, secret: String?, credentials: [Credential]?) {
        self.id = id
        self.scheme = scheme
        self.secret = secret
        self.cred = credentials
    }

    func addCred(c: Credential) {
        if cred == nil {
            cred = []
        }
        cred!.append(c)
    }
}

public class MetaGetData: Codable {
    /// Load messages/ranges with IDs equal or greater than this (inclusive or closed).
    let since: Int?
    /// Load messages/ranges with IDs lower than this (exclusive or open).
    let before: Int?
    /// Limit the number of messages loaded.
    let limit: Int?
    init(since: Int?, before: Int?, limit: Int?) {
        self.since = since
        self.before = before
        self.limit = limit
    }
}
public class MetaGetDesc: Codable {
    // ims = If modified since...
    let ims: Date?
    public init(ims: Date? = nil) {
        self.ims = ims
    }
}
public class MetaGetSub: Codable {
    let user: String?
    let ims: Date?
    let limit: Int?
    public init(user: String?, ims: Date?, limit: Int?) {
        self.user = user
        self.ims = ims
        self.limit = limit
    }
}
public class MsgGetMeta: CustomStringConvertible, Codable {
    private static let kDescSet = 0x01
    private static let kSubSet = 0x02
    private static let kDataSet = 0x04
    private static let kDelSet = 0x08
    private static let kTagsSet = 0x10
    private static let kCredSet = 0x20

    static let kDesc = "desc"
    static let kSub = "sub"
    static let kData = "data"
    static let kDel = "del"
    static let kTags = "tags"
    static let kCred = "cred"

    private var set = 0

    public var what: String = ""
    public var desc: MetaGetDesc?
    public var sub: MetaGetSub?
    public var data: MetaGetData?
    public var del: MetaGetData?

    // Only use these fields in JSON representation.
    private enum CodingKeys: String, CodingKey {
        case what
        case desc
        case sub
        case data
        case del
    }

    public var description: String {
        // return
        let desc_str = desc != nil ? String(describing: desc!) : "nil"
        let sub_str = sub != nil ? String(describing: sub!) : "nil"
        let data_str = data != nil ? String(describing: data!) : "nil"
        let del_str = del != nil ? String(describing: del!) : "nil"
        return "[\(self.what)]" +
            " desc=[\(desc_str)]," +
            " sub=[\(sub_str)]," +
            " data=[\(data_str)]," +
            " del=[\(del_str)]" +
            " tags=[\((set & MsgGetMeta.kTagsSet) != 0 ? "set" : "nil")]" +
            " cred=[\((set & MsgGetMeta.kCredSet) != 0 ? "set" : "nil")]"
    }

    init() {
        self.what = "\(MsgGetMeta.kDesc) \(MsgGetMeta.kData) \(MsgGetMeta.kDel) \(MsgGetMeta.kTags)"
    }
    public init(desc: MetaGetDesc?, sub: MetaGetSub?, data: MetaGetData?, del: MetaGetData?, tags: Bool, cred: Bool) {
        self.desc = desc
        self.sub = sub
        self.data = data
        self.del = del
        if tags {
            self.set = MsgGetMeta.kTagsSet
        }
        if cred {
            self.set |= MsgGetMeta.kCredSet
        }
        buildWhat()
    }
    private func buildWhat() {
        var parts: [String] = []
        if (self.set & MsgGetMeta.kDescSet) != 0 || self.desc != nil {
            parts.append(MsgGetMeta.kDesc)
        }
        if (self.set & MsgGetMeta.kSubSet) != 0 || self.sub != nil {
            parts.append(MsgGetMeta.kSub)
        }
        if (self.set & MsgGetMeta.kDataSet) != 0 || self.data != nil {
            parts.append(MsgGetMeta.kData)
        }
        if (self.set & MsgGetMeta.kDelSet) != 0 || self.del != nil {
            parts.append(MsgGetMeta.kDel)
        }
        if (self.set & MsgGetMeta.kTagsSet) != 0 {
            parts.append(MsgGetMeta.kTags)
        }
        if (self.set & MsgGetMeta.kCredSet) != 0 {
            parts.append(MsgGetMeta.kCred)
        }
        self.what = parts.joined(separator: " ")
    }

    func setData(since: Int?, before: Int?, limit: Int?) {
        if since != nil || before != nil || limit != nil {
            data = MetaGetData(since: since, before: before, limit: limit)
        }
        set |= MsgGetMeta.kDataSet
        buildWhat()
    }
    func setDesc(ims: Date?) {
        if ims != nil {
            desc = MetaGetDesc(ims: ims)
        }
        set |= MsgGetMeta.kDescSet
        buildWhat()
    }
    func setSub(user: String?, ims: Date?, limit: Int?) {
        if user != nil || ims != nil || limit != nil {
            sub = MetaGetSub(user: user, ims: ims, limit: limit)
        }
        set |= MsgGetMeta.kSubSet
        buildWhat()
    }
    func setDel(since: Int?, limit: Int?) {
        if since != nil || limit != nil {
            del = MetaGetData(since: since, before: nil, limit: limit)
        }
        set |= MsgGetMeta.kDelSet
        buildWhat()
    }
    func setTags() {
        set |= MsgGetMeta.kTagsSet
        buildWhat()
    }
    func setCred() {
        set |= MsgGetMeta.kCredSet
        buildWhat()
    }
    private init(what: String) {
        self.what = what
    }
    public static func sub() -> MsgGetMeta {
        return MsgGetMeta(what: kSub)
    }
    public static func desc() -> MsgGetMeta {
        return MsgGetMeta(what: kDesc)
    }
}

public class MetaSetDesc<P: Codable, R: Codable>: Codable {
    var defacs: Defacs?
    var pub: P?
    var priv: R?
    var trusted: TrustedType?

    // Not serialized
    public var attachments: [String]?

    private enum CodingKeys: String, CodingKey {
        case defacs, pub = "public", priv = "private", trusted
    }
    public init(da: Defacs) {
        self.defacs = da
    }
    public init(pub: P?, priv: R?) {
        self.pub = pub
        self.priv = priv
        self.trusted = nil
    }
    public init(auth: String, anon: String) {
        self.defacs = Defacs(auth: auth, anon: anon)
    }
}

public class MetaSetSub: Codable {
    let user: String?
    let mode: String?
    public init() {
        self.user = nil
        self.mode = nil
    }
    public init(mode: String?) {
        self.user = nil
        self.mode = mode
    }
    public init(user: String?, mode: String?) {
        self.user = user
        self.mode = mode
    }
}
public class MsgSetMeta<Pu: Codable, Pr: Codable>: Codable {
    let desc: MetaSetDesc<Pu, Pr>?
    let sub: MetaSetSub?
    let tags: [String]?
    let cred: Credential?

    public init(desc: MetaSetDesc<Pu, Pr>?, sub: MetaSetSub?, tags: [String]?, cred: Credential?) {
        self.desc = desc
        self.sub = sub
        self.tags = tags
        self.cred = cred
    }
}

public class MsgClientSub<Pu: Codable, Pr: Codable>: Codable {
    var id: String?
    var topic: String?
    var set: MsgSetMeta<Pu, Pr>?
    var get: MsgGetMeta?
    init(id: String?, topic: String?, set: MsgSetMeta<Pu, Pr>?, get: MsgGetMeta?) {
        self.id = id
        self.topic = topic
        self.set = set
        self.get = get
    }
}

public class MsgClientGet: Codable {
    let id: String?
    let topic: String?
    let what: String?
    let desc: MetaGetDesc?
    let sub: MetaGetSub?
    let data: MetaGetData?

    init(id: String, topic: String, query: MsgGetMeta) {
        self.id = id
        self.topic = topic
        self.what = query.what
        self.desc = query.desc
        self.sub = query.sub
        self.data = query.data
    }
}

public class MsgClientSet<Pu: Codable, Pr: Codable>: Codable {
    let id: String?
    let topic: String?
    let desc: MetaSetDesc<Pu, Pr>?
    let sub: MetaSetSub?
    let tags: [String]?
    let cred: Credential?
    init(id: String, topic: String, desc: MetaSetDesc<Pu, Pr>?, sub: MetaSetSub?, tags: [String]?, cred: Credential?) {
        self.id = id
        self.topic = topic
        self.desc = desc
        self.sub = sub
        self.tags = tags
        self.cred = cred
    }
    convenience init(id: String, topic: String, meta: MsgSetMeta<Pu, Pr>?) {
        self.init(id: id, topic: topic, desc: meta?.desc, sub: meta?.sub, tags: meta?.tags, cred: meta?.cred)
    }
}

public class MsgClientLeave: Codable {
    let id: String?
    let topic: String?
    let unsub: Bool?
    init(id: String?, topic: String?, unsub: Bool?) {
        self.id = id
        self.topic = topic
        self.unsub = unsub
    }
}

/// Typing, read/received and video call notifications packet.
public class MsgClientNote: Codable {
    let topic: String?
    let what: String?
    let seq: Int?
    // Event (set only when what="call")
    let event: String?
    // Arbitrary json payload (set only when what="call")
    let payload: JSONValue?

    init(topic: String, what: String, seq: Int, event: String? = nil, payload: JSONValue? = nil) {
        self.topic = topic
        self.what = what
        self.seq = seq > 0 ? seq : nil
        self.event = event
        self.payload = payload
    }
}

public class MsgClientPub: Codable {
    let id: String?
    let topic: String?
    let noecho: Bool?
    let head: [String: JSONValue]?
    let content: Drafty?

    init(id: String?, topic: String?, noecho: Bool?, head: [String: JSONValue]?, content: Drafty?) {
        self.id = id
        self.topic = topic
        self.noecho = noecho
        self.head = head
        self.content = content
    }
}

public class MsgClientDel: Codable {
    static let kStrTopic = "topic"
    static let kStrMsg = "msg"
    static let kStrSub = "sub"
    static let kStrUser = "user"
    static let kStrCred = "cred"
    let id: String?
    let topic: String?
    let what: String?
    let delseq: [MsgRange]?
    let user: String?
    let hard: Bool?
    let cred: Credential?

    init(id: String?, topic: String?, what: String?, ranges: [MsgRange]?, user: String?, cred: Credential?, hard: Bool?) {
        self.id = id
        self.topic = topic
        self.what = what
        // nil value will cause the field to be skipped
        // during serialization instead of sending 0/null/[].
        self.delseq = what == MsgClientDel.kStrMsg ? ranges : nil
        self.user = what == MsgClientDel.kStrSub || what == MsgClientDel.kStrUser ? user : nil
        self.hard = (hard ?? false) ? true : nil
        self.cred = cred
    }

    /// Delete multiple message ranges.
    convenience init(id: String?, topic: String, ranges: [MsgRange]?, hard: Bool?) {
        self.init(id: id, topic: topic, what: MsgClientDel.kStrMsg,
                  ranges: ranges,
                  user: nil, cred: nil, hard: hard)
    }
    /// Delete range of messages.
    convenience init(id: String?, topic: String, from: Int, to: Int?, hard: Bool?) {
        self.init(id: id, topic: topic, what: MsgClientDel.kStrMsg,
                  ranges: [MsgRange(low: from, hi: to)],
                  user: nil, cred: nil, hard: hard)
    }

    /// Delete message by id
    convenience init(id: String?, topic: String, msgId: Int, hard: Bool?) {
        self.init(id: id, topic: topic, what: MsgClientDel.kStrMsg,
                  ranges: [MsgRange(id: msgId)],
                  user: nil, cred: nil, hard: hard)
    }

    /// Delete topic
    convenience init(id: String?, topic: String, hard: Bool) {
        self.init(id: id, topic: topic, what: MsgClientDel.kStrTopic,
                  ranges: nil, user: nil, cred: nil, hard: hard)
    }

    /// Delete current user.
    convenience init(id: String?, hard: Bool) {
        self.init(id: id, topic: nil, what: MsgClientDel.kStrUser,
                  ranges: nil, user: nil, cred: nil, hard: hard)
    }

    /// Delete subscription
    convenience init(id: String?, topic: String, user: String?) {
        self.init(id: id, topic: topic, what: MsgClientDel.kStrSub,
                  ranges: nil, user: user, cred: nil, hard: nil)
    }

    /// Delete credential
    convenience init(id: String?, cred: Credential) {
        self.init(id: id, topic: Tinode.kTopicMe, what: MsgClientDel.kStrCred,
                  ranges: nil, user: nil, cred: cred, hard: nil)
    }

}

public class MsgClientExtra: Codable {
    let attachments: [String]?

    init(attachments: [String]?) {
        self.attachments = attachments
    }
}

public class ClientMessage<Pu: Codable, Pr: Codable>: Codable {
    public var hi: MsgClientHi?
    public var acc: MsgClientAcc<Pu, Pr>?
    public var login: MsgClientLogin?
    public var sub: MsgClientSub<Pu, Pr>?
    public var get: MsgClientGet?
    public var set: MsgClientSet<Pu, Pr>?
    public var leave: MsgClientLeave?
    public var note: MsgClientNote?
    public var pub: MsgClientPub?
    public var del: MsgClientDel?

    // Optional field for sending attachment references.
    var extra: MsgClientExtra?

    init(hi: MsgClientHi) {
        self.hi = hi
    }
    init(acc: MsgClientAcc<Pu, Pr>) {
        self.acc = acc
    }
    init(login: MsgClientLogin) {
        self.login = login
    }
    init(sub: MsgClientSub<Pu, Pr>) {
        self.sub = sub
    }
    init(get: MsgClientGet) {
        self.get = get
    }
    init(set: MsgClientSet<Pu, Pr>) {
        self.set = set
    }
    init(leave: MsgClientLeave) {
        self.leave = leave
    }
    init(note: MsgClientNote) {
        self.note = note
    }
    init(pub: MsgClientPub) {
        self.pub = pub
    }
    init(del: MsgClientDel) {
        self.del = del
    }
}
