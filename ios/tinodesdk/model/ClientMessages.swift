//
//  ClientMessages.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

class MsgClientHi : Encodable {
    let id: String?
    let ver: String?
    // User Agent.
    let ua: String?
    // Device ID.
    let dev: String?
    let lang: String?
    
    init(id: String, ver: String, ua: String, dev: String, lang: String) {
        self.id = id
        self.ver = ver
        self.ua = ua
        self.dev = dev
        self.lang = lang
    }
}

class Credential: Encodable {
    // Confirmation method: email, phone, captcha.
    var meth: String? = nil
    // Credential to be confirmed, e.g. email or a phone number.
    var val: String? = nil
    // Confirmation response, such as '123456'.
    var resp: String? = nil
    // Confirmation parameters.
    var params: [String:String]? = nil
    
    init(meth: String, val: String) {
        self.meth = meth
        self.val = val
    }
    
    init(meth: String?, val: String?, resp: String?, params: [String:String]?) {
        self.meth = meth
        self.val = val
        self.resp = resp
        self.params = params
    }
}

class MsgClientAcc<Pu: Encodable,Pr: Encodable>: Encodable {
    var id: String?
    var user: String?
    var scheme: String?
    var secret: String?
    var login: Bool?
    var tags: [String]?
    var cred: [Credential]?
    var desc: MetaSetDesc<Pu,Pr>
    
    init(id: String?,
         uid: String?,
         scheme: String?,
         secret: String?,
         doLogin: Bool,
         desc: MetaSetDesc<Pu,Pr>) {
        self.id = id
        self.user = uid == nil ? "new" : uid
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

class MsgClientLogin: Encodable {
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

class MetaGetData: Encodable {
    let since: Int?
    let before: Int?
    let limit: Int?
    init(since: Int?, before: Int?, limit: Int?) {
        self.since = since
        self.before = before
        self.limit = limit
    }
}
class MetaGetDesc: Encodable {
    // ims = If modified since...
    let ims: Date?
    init(ims: Date?) {
        self.ims = ims
    }
}
class MetaGetSub: Encodable {
    let user: String?
    let ims: Date?
    let limit: Int?
    init(user: String?, ims: Date?, limit: Int?) {
        self.user = user
        self.ims = ims
        self.limit = limit
    }
}
class MsgGetMeta: CustomStringConvertible, Encodable {
    private static let kDescSet = 0x01
    private static let kSubSet = 0x02
    private static let kDataSet = 0x04
    private static let kDelSet = 0x08
    private static let kTagsSet = 0x10
    
    static let kDesc = "desc"
    static let kSub = "sub"
    static let kData = "data"
    static let kDel = "del"
    static let kTags = "tags"
    
    private var set = 0
    
    var what: String = ""
    var desc: MetaGetDesc? = nil
    var sub: MetaGetSub? = nil
    var data: MetaGetData? = nil
    var del: MetaGetData? = nil
    
    // Only use these fields in JSON representation.
    private enum CodingKeys: String, CodingKey {
        case what
        case desc
        case sub
        case data
        case del
    }
    
    var description: String {
        //return
        let desc_str = desc != nil ? String(describing: desc!) : "null"
        let sub_str = sub != nil ? String(describing: sub!) : "null"
        let data_str = data != nil ? String(describing: data!) : "null"
        let del_str = del != nil ? String(describing: del!) : "null"
        return "[\(self.what)]" +
            " desc=[\(desc_str)]," +
            " sub=[\(sub_str)]," +
            " data=[\(data_str)]," +
            " del=[\(del_str)]" +
        " tags=[\((set & MsgGetMeta.kTagsSet) != 0 ? "set" : "null")]"
    }
    
    init() {
        self.what = "\(MsgGetMeta.kDesc) \(MsgGetMeta.kData) \(MsgGetMeta.kDel) \(MsgGetMeta.kTags)"
    }
    
    init(desc: MetaGetDesc?, sub: MetaGetSub?, data: MetaGetData?, del: MetaGetData?, tags: Bool) {
        self.desc = desc
        self.sub = sub
        self.data = data
        self.del = del
        if tags {
            self.set = MsgGetMeta.kTagsSet
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
    
    private init(what: String) {
        self.what = what
    }
    
    static func sub() -> MsgGetMeta {
        return MsgGetMeta(what: kSub)
    }
}

class MetaSetDesc<P: Encodable, R: Encodable>: Encodable {
    var defacs: Defacs? = nil
    var pub: P? = nil
    var priv: R? = nil
    
    init(pub: P, priv: R) {
        self.pub = pub
        self.priv = priv
    }
    
    init(da: Defacs) {
        self.defacs = da
    }
    init(pub: P?, priv: R?) {
        self.pub = pub
        self.priv = priv
    }
    init(auth: String, anon: String) {
        self.defacs = Defacs(auth: auth, anon: anon)
    }
    
    enum CodingKeys : String, CodingKey {
        case pub = "public"
        case priv = "private"
    }
}

class MetaSetSub: Encodable {
    let user: String? = nil
    let mode: String? = nil
}
class MsgSetMeta<Pu: Encodable, Pr: Encodable>: Encodable {
    let desc: MetaSetDesc<Pu, Pr>?
    let sub: MetaSetSub?
    let tags: [String]?
    
    init(desc: MetaSetDesc<Pu, Pr>?, sub: MetaSetSub?, tags: [String]?) {
        self.desc = desc
        self.sub = sub
        self.tags = tags
    }
}

class MsgClientSub<Pu: Encodable, Pr: Encodable>: Encodable {
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

class MsgClientGet: Encodable {
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

class MsgClientLeave: Encodable {
    let id: String?
    let topic: String?
    let unsub: Bool?
    init(id: String?, topic: String?, unsub: Bool?) {
        self.id = id
        self.topic = topic
        self.unsub = unsub
    }
}

class MsgClientNote: Encodable {
    let topic: String?
    let what: String?
    let seq: Int?
    
    init(topic: String, what: String, seq: Int) {
        self.topic = topic
        self.what = what
        self.seq = seq > 0 ? seq : nil
    }
}

class MsgClientPub: Encodable {
    let id: String?
    let topic: String?
    let noecho: Bool?
    let head: [String:JSONValue]?
    let content: JSONValue?
    init(id: String?, topic: String?, noecho: Bool?, head: [String:JSONValue]?, content: JSONValue?) {
        self.id = id
        self.topic = topic
        self.noecho = noecho
        self.head = head
        self.content = content
    }
}

class ClientMessage<Pu: Encodable, Pr: Encodable> : Encodable {
    var hi: MsgClientHi?
    var acc: MsgClientAcc<Pu,Pr>?
    var login: MsgClientLogin?
    var sub: MsgClientSub<Pu, Pr>?
    var get: MsgClientGet?
    var leave: MsgClientLeave?
    var note: MsgClientNote?
    var pub: MsgClientPub?
    
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
    init(leave: MsgClientLeave) {
        self.leave = leave
    }
    init(note: MsgClientNote) {
        self.note = note
    }
    init(pub: MsgClientPub) {
        self.pub = pub
    }
}
