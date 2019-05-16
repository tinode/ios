//
//  MessageTypes.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

public class MsgServerCtrl: Decodable {
    public let id: String?
    public let topic: String?
    public let code: Int
    public let text: String
    public let ts: Date
    public let params: [String: JSONValue]?

    public func getStringParam(for key: String) -> String? {
        if case let .string(v)? = params?[key] {
            return v
        }
        return nil
    }
    
    public func getStringArray(for key: String) -> [String]? {
        if case .array(let  v)? = params?[key] {
            return v.compactMap { element -> String? in
                if case .string(let s) = element {
                    return s
                }
                return nil
            }
        }
        return nil
    }
    
    public func getIntParam(for key: String) -> Int? {
        if case let .int(v)? = params?[key] {
            return v
        }
        return nil
    }
    public func getStringDict(for key: String) -> [String:String]? {
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

public class MsgDelRange: Codable {
    public var low: Int? = nil
    public var hi: Int? = nil
    
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

    static func listToRanges(list: [Int]?) -> [MsgDelRange]? {
        guard var list = list else { return nil }
        guard list.count > 0 else { return [] }
        list.sort()
        var res = [MsgDelRange]()
        var first = list[0]
        var last = first
        for i in 1..<list.count {
            let cur = list[i]
            if cur == last { continue }
            if cur > last + 1 {
                res.append(MsgDelRange(low: first, hi: last + 1))
                first = cur
            }
            last = cur
        }
        res.append(MsgDelRange(low: first, hi: last + 1))
        return res
    }
}

public class DelValues: Decodable {
    let clear: Int
    let delseq: [MsgDelRange]
}

public typealias PrivateType = Dictionary<String, JSONValue>

// VCard
public typealias DefaultDescription = Description<VCard, PrivateType>
public typealias DefaultSubscription = Subscription<VCard, PrivateType>
public typealias FndDescription = Description<String, String>
public typealias FndSubscription = Subscription<VCard, Array<String>>

public class MsgServerMeta: Decodable {
    public let id: String?
    public let topic: String?
    public let ts: Date?
    public let desc: DescriptionProto?
    public let sub: [SubscriptionProto]?
    public let del: DelValues?
    public let tags: [String]?
    
    private enum CodingKeys: String, CodingKey  {
        case id, topic, ts, desc, sub, del, tags
    }
    required public init (from decoder: Decoder) throws {
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

open class MsgServerData : Decodable {
    public var id: String?
    public var topic: String?
    public var head: [String:JSONValue]?
    public var from: String?
    public var ts: Date?
    public var seq: Int?
    public var getSeq: Int {
        get { return seq ?? 0 }
    }
    // todo: make it drafty
    public var content: Drafty?
    public init() {}
}

public class AccessChange : Decodable {
    let want: String?
    let given: String?
}

public class MsgServerPres : Decodable {
    enum What {
        case kOn, kOff, kUpd, kGone, kAcs, kMsg, kUa, kRecv, kRead, kDel, kUnknown
    }
    public var topic: String?
    public var src: String?
    public var what: String?
    public var seq: Int?
    public var clear: Int?
    public var delseq: [MsgDelRange]?
    public var ua: String?
    public var act: String?
    public var tgt: String?
    public var dacs: AccessChange?
    
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

public class MsgServerInfo: Decodable {
    public var topic: String?
    public var from: String?
    public var what: String?
    public var seq: Int?
}

public class ServerMessage: Decodable {
    public var ctrl: MsgServerCtrl?
    public var meta: MsgServerMeta?
    public var data: MsgServerData?
    public var pres: MsgServerPres?
    public var info: MsgServerInfo?
    public init() {}
}
