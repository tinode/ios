//
//  ClientMessages.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

public class MsgClientHi : Encodable {
    let id: String?
    let ver: String?
    // User Agent.
    let ua: String?
    // Push notification token.
    let dev: String?
    let lang: String?
    let bkg: Bool?

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
    public var meth: String? = nil
    // Credential to be confirmed, e.g. email or a phone number.
    public var val: String? = nil
    // Confirmation response, such as '123456'.
    var resp: String? = nil
    // Confirmation parameters.
    var params: [String:String]? = nil
    // If credential is confirmed
    var done: Bool? = nil

    public init(meth: String, val: String) {
        self.meth = meth
        self.val = val
    }

    public init(meth: String?, val: String?, resp: String?, params: [String:String]?) {
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

public class MsgClientAcc<Pu: Encodable,Pr: Encodable>: Encodable {
    var id: String?
    var user: String?
    var scheme: String?
    var secret: String?
    var login: Bool?
    var tags: [String]?
    var cred: [Credential]?
    var desc: MetaSetDesc<Pu,Pr>?

    init(id: String?,
         uid: String?,
         scheme: String?,
         secret: String?,
         doLogin: Bool,
         desc: MetaSetDesc<Pu,Pr>?) {
        self.id = id
        self.user = uid
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

public class MsgClientLogin: Encodable {
    let id: String?
    let scheme: String?
    let secret: String?
    var cred: [Credential]?

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

public class MetaGetData: Encodable {
    let since: Int?
    let before: Int?
    let limit: Int?
    init(since: Int?, before: Int?, limit: Int?) {
        self.since = since
        self.before = before
        self.limit = limit
    }
}
public class MetaGetDesc: Encodable {
    // ims = If modified since...
    let ims: Date?
    public init(ims: Date? = nil) {
        self.ims = ims
    }
}
public class MetaGetSub: Encodable {
    let user: String?
    let ims: Date?
    let limit: Int?
    public init(user: String?, ims: Date?, limit: Int?) {
        self.user = user
        self.ims = ims
        self.limit = limit
    }
}
public class MsgGetMeta: CustomStringConvertible, Encodable {
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
    public var desc: MetaGetDesc? = nil
    public var sub: MetaGetSub? = nil
    public var data: MetaGetData? = nil
    public var del: MetaGetData? = nil

    // Only use these fields in JSON representation.
    private enum CodingKeys: String, CodingKey {
        case what
        case desc
        case sub
        case data
        case del
    }

    public var description: String {
        //return
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

public class MetaSetDesc<P: Encodable, R: Encodable>: Encodable {
    var defacs: Defacs? = nil
    var pub: P? = nil
    var priv: R? = nil
    private enum CodingKeys : String, CodingKey {
        case defacs, pub = "public", priv = "private"
    }
    public init(da: Defacs) {
        self.defacs = da
    }
    public init(pub: P?, priv: R?) {
        self.pub = pub
        self.priv = priv
    }
    public init(auth: String, anon: String) {
        self.defacs = Defacs(auth: auth, anon: anon)
    }
}

public class MetaSetSub: Encodable {
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
public class MsgSetMeta<Pu: Encodable, Pr: Encodable>: Encodable {
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

public class MsgClientSub<Pu: Encodable, Pr: Encodable>: Encodable {
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

public class MsgClientGet: Encodable {
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

public class MsgClientSet<Pu: Encodable, Pr: Encodable>: Encodable {
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

public class MsgClientLeave: Encodable {
    let id: String?
    let topic: String?
    let unsub: Bool?
    init(id: String?, topic: String?, unsub: Bool?) {
        self.id = id
        self.topic = topic
        self.unsub = unsub
    }
}

public class MsgClientNote: Encodable {
    let topic: String?
    let what: String?
    let seq: Int?

    init(topic: String, what: String, seq: Int) {
        self.topic = topic
        self.what = what
        self.seq = seq > 0 ? seq : nil
    }
}

public class MsgClientPub: Encodable {
    let id: String?
    let topic: String?
    let noecho: Bool?
    let head: [String:JSONValue]?
    let content: Drafty?

    init(id: String?, topic: String?, noecho: Bool?, head: [String:JSONValue]?, content: Drafty?) {
        self.id = id
        self.topic = topic
        self.noecho = noecho
        self.head = head
        self.content = content
    }
}

public class MsgClientDel: Encodable {
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

public class ClientMessage<Pu: Encodable, Pr: Encodable> : Encodable {
    var hi: MsgClientHi?
    var acc: MsgClientAcc<Pu,Pr>?
    var login: MsgClientLogin?
    var sub: MsgClientSub<Pu, Pr>?
    var get: MsgClientGet?
    var set: MsgClientSet<Pu, Pr>?
    var leave: MsgClientLeave?
    var note: MsgClientNote?
    var pub: MsgClientPub?
    var del: MsgClientDel?

    init(hi: MsgClientHi) {
        self.hi = hi
    }
    init(acc: MsgClientAcc<Pu,Pr>) {
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
