//
//  MessageTypes.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

class MsgServerCtrl : Decodable {
    let id: String?
    let topic: String?
    let code: Int
    let text: String
    let ts: Date
    let params: [String: JSONValue]?

    func getStringParam(for key: String) -> String? {
        if case let .string(v)? = params?[key] {
            return v
        }
        return nil
    }
    
    func getIntParam(for key: String) -> Int? {
        if case let .int(v)? = params?[key] {
            return v
        }
        return nil
    }
    func getStringDict(for key: String) -> [String:String]? {
        if case .dict(let  v)? = params?[key] {
            return v.mapValues { (value) -> String? in
                if case .string(let s) = value {
                    return s
                }
                return nil
            }.filter { $0.1 != nil }.mapValues { $0! }
        }
        return nil
    }
}

class MsgDelRange: Codable {
    var low: Int? = nil
    var hi: Int? = nil
    
    init() {
        low = 0
    }
    
    init(id: Int) {
        low = id
    }
    
    init(low: Int, hi: Int) {
        self.low = low
        self.hi = hi
    }
}

class DelValues: Decodable {
    let clear: Int
    let delseq: [MsgDelRange]
}

typealias PrivateType = Dictionary<String, JSONValue>

// VCard
typealias DefaultDescription = Description<VCard, PrivateType>
typealias DefaultSubscription = Subscription<VCard, PrivateType>
typealias FndDescription = Description<String, String>
typealias FndSubscription = Subscription<VCard, Array<String>>

class MsgServerMeta: Decodable {
    let id: String?
    let topic: String?
    let ts: Date?
    let desc: DescriptionProto?
    let sub: [SubscriptionProto]?
    let del: DelValues?
    let tags: [String]?
    
    private enum CodingKeys: String, CodingKey  {
        case id, topic, ts, desc, sub, del, tags
    }
    required init (from decoder: Decoder) throws {
        let container =  try decoder.container (keyedBy: CodingKeys.self)
        id = try? container.decode(String.self, forKey: .id)
        topic = try? container.decode(String.self, forKey: .topic)
        ts = try? container.decode(Date.self, forKey: .ts)
        del = try? container.decode(DelValues.self, forKey: .del)
        tags = try? container.decode(Array<String>.self, forKey: .tags)
        if topic == Tinode.kTopicMe {
            desc = try? container.decode(DefaultDescription.self, forKey: .desc)
            sub = try? container.decode(Array<DefaultSubscription>.self, forKey: .sub)
        } else if topic == Tinode.kTopicFnd {
            desc = try? container.decode(FndDescription.self, forKey: .desc)
            sub = try? container.decode(Array<FndSubscription>.self, forKey: .sub)
        } else {
            desc = try? container.decode(DefaultDescription.self, forKey: .desc)
            sub = try? container.decode(Array<DefaultSubscription>.self, forKey: .sub)
        }
    }
}

class MsgServerData : Decodable {
    var id: String?
    var topic: String?
    var head: [String:JSONValue]?
    var from: String?
    var ts: Date?
    var seq: Int?
    var getSeq: Int {
        get { return seq ?? 0 }
    }
    // todo: make it drafty
    var content: String?//Drafty?
}

class AccessChange : Decodable {
    let want: String?
    let given: String?
}

class MsgServerPres : Decodable {
    enum What {
        case kOn, kOff, kUpd, kGone, kAcs, kMsg, kUa, kRecv, kRead, kDel, kUnknown
    }
    var topic: String?
    var src: String?
    var what: String?
    var seq: Int?
    var clear: Int?
    var delseq: [MsgDelRange]?
    var ua: String?
    var act: String?
    var tgt: String?
    var dacs: AccessChange?
    
    static func parseWhat(what: String?) -> What {
        guard let what = what else {
            return .kUnknown
        }
        switch what {
        case "on":
            return .kOn
        case "off":
            return .kOff
        case "upd":
            return .kUpd
        case "acs":
            return .kAcs
        case "gone":
            return .kGone
        case "msg":
            return .kMsg
        case "ua":
            return .kUa
        case "recv":
            return .kRecv
        case "read":
            return .kRead
        case "del":
            return .kDel
        default:
            return .kUnknown
        }
    }
}

class MsgServerInfo: Decodable {
    var topic: String?
    var from: String?
    var what: String?
    var seq: Int?
}

class ServerMessage : Decodable {
    var ctrl: MsgServerCtrl?
    var meta: MsgServerMeta?
    var data: MsgServerData?
    var pres: MsgServerPres?
    var info: MsgServerInfo?
}
