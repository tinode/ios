//
//  MessageTypes.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

public class MsgServerCtrl: Decodable {
    public let id: String?
    public let topic: String?
    public let code: Int
    public let text: String
    public let ts: Date
    public let params: [String: JSONValue]?

    public func getBoolParam(for key: String) -> Bool? {
        if case let .bool(v)? = params?[key] {
            return v
        }
        return nil
    }

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

    public func getInt64Param(for key: String) -> Int64? {
        guard let val = params?[key] else { return nil }
        return val.asInt64()
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

public class DelValues: Decodable {
    let clear: Int
    let delseq: [MsgRange]
}

public class MsgServerMeta: Decodable {
    public let id: String?
    public let topic: String?
    public let ts: Date?
    public let desc: DescriptionProto?
    public let sub: [SubscriptionProto]?
    public let del: DelValues?
    public let tags: [String]?
    public let cred: [Credential]?

    private enum CodingKeys: String, CodingKey  {
        case id, topic, ts, desc, sub, del, tags, cred
    }
    required public init (from decoder: Decoder) throws {
        let container =  try decoder.container (keyedBy: CodingKeys.self)
        id = try? container.decode(String.self, forKey: .id)
        topic = try? container.decode(String.self, forKey: .topic)
        ts = try? container.decode(Date.self, forKey: .ts)
        del = try? container.decode(DelValues.self, forKey: .del)
        tags = try? container.decode(Array<String>.self, forKey: .tags)
        cred = try? container.decode(Array<Credential>.self, forKey: .cred)
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
    public var getSeq: Int { return seq ?? 0 }
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
        case kOn, kOff, kUpd, kGone, kTerm, kAcs, kMsg, kUa, kRecv, kRead, kDel, kTags, kUnknown
    }
    public var topic: String?
    public var src: String?
    public var what: String?
    public var seq: Int?
    public var clear: Int?
    public var delseq: [MsgRange]?
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
        case "term":
            return .kTerm
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
        case "tags":
            return .kTags
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
    // RFC 7231 HTTP status messages
    // https://tools.ietf.org/html/rfc7231#section-6
    public static let kStatusOk                  = 200 // 6.3.1
    public static let kStatusResetContent        = 205 // 6.3.6
    public static let kStatusMultipleChoices     = 300 // 6.4.1
    public static let kStatusSeeOther            = 303 // 6.4.4
    public static let kStatusBadRequest          = 400 // 6.5.1
    public static let kStatusUnauthorized        = 401 // 3.1
    public static let kStatusInternalServerError = 500 // 6.6.1
    public static let kStatusServiceUnavailable  = 503 // 6.6.4
    public static let kStatusGatewayTimeout      = 504 // 6.6.5

    public var ctrl: MsgServerCtrl?
    public var meta: MsgServerMeta?
    public var data: MsgServerData?
    public var pres: MsgServerPres?
    public var info: MsgServerInfo?
    public init() {}
}
