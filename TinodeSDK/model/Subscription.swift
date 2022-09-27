//
//  Subscription.swift
//  ios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import Foundation

public class LastSeen: Codable {
    public var when: Date?
    public var ua: String?
    public init(when: Date?, ua: String?) {
        self.when = when
        self.ua = ua
    }
    public func merge(seen: LastSeen?) -> Bool {
        var changed = false
        if let s = seen {
            if let w = s.when, self.when == nil || self.when! < w {
                self.when = w
                ua = s.ua
                changed = true
            }
        }
        return changed
    }
}

// Messages may send subscriptions with different
// public and private types. We need to have a common type
// to handle subscriptions with all these types.
public protocol SubscriptionProto: AnyObject, Decodable {
    var user: String? { get set }
    var topic: String? { get set }
    var updated: Date? { get set }
    var deleted: Date? { get set }
    var payload: Payload? { get set }
    var acs: Acs? { get set }
    var read: Int? { get set }
    var getRead: Int { get }
    var recv: Int? { get set }
    var getRecv: Int { get }
    var seq: Int? { get set }
    var getSeq: Int { get }
    var clear: Int? { get set }
    var getClear: Int { get }
    var seen: LastSeen? { get set }
    var uniqueId: String? { get }
    func serializePub() -> String?
    @discardableResult
    func deserializePub(from data: String?) -> Bool
    func serializePriv() -> String?
    @discardableResult
    func deserializePriv(from data: String?) -> Bool
    func serializeTrusted() -> String?
    @discardableResult
    func deserializeTrusted(from data: String?) -> Bool

    static func createByName(name: String?) -> SubscriptionProto?
}

extension SubscriptionProto {
    public static func createByName(name: String?) -> SubscriptionProto? {
        guard let name = name else { return nil }
        switch name {
        case String(describing: DefaultSubscription.self):
            return DefaultSubscription()
        case String(describing: FndSubscription.self):
            return FndSubscription()
        default:
            return nil
        }
    }
}

public class Subscription<SP: Codable, SR: Codable>: Codable, SubscriptionProto {
    public var user: String?
    public var updated: Date?
    public var deleted: Date?
    public var touched: Date?

    public var acs: Acs?
    public var read: Int? = 0
    public var getRead: Int { return read ?? 0 }
    public var recv: Int? = 0
    public var getRecv: Int { return recv ?? 0 }
    public var priv: SR?
    public var online: Bool?

    public var topic: String?
    public var seq: Int? = 0
    public var getSeq: Int { return seq ?? 0 }
    public var clear: Int? = 0
    public var getClear: Int { return clear ?? 0 }
    public var pub: SP?
    public var trusted: TrustedType?
    public var seen: LastSeen?
    public var payload: Payload?

    public var uniqueId: String? {
        if topic == nil {
            return user
        }
        if user == nil {
            return topic
        }
        return topic! + ":" + user!
    }

    private enum CodingKeys: String, CodingKey {
        case user, updated, deleted, touched,
             acs, read, recv, priv = "private", online,
             topic, seq, clear, pub = "public", trusted, seen
    }

    func updateAccessMode(ac: AccessChange?) {
        if acs == nil {
            acs = Acs(from: nil as Acs?)
        }
        acs!.update(from: ac)
    }

    func merge(sub: Subscription<SP, SR>) -> Bool {
        var changed = false
        if user == nil && !(sub.user?.isEmpty ?? true) {
            user = sub.user
            changed = true
        }
        if sub.updated != nil && (updated == nil || updated! < sub.updated!) {
            updated = sub.updated
            if sub.pub != nil {
                pub = sub.pub
            }
            if sub.trusted != nil {
                trusted = sub.trusted
            }
            changed = true
        } else {
            if pub == nil && sub.pub != nil {
                pub = sub.pub
            }
            if trusted == nil && sub.trusted != nil {
                trusted = sub.trusted
            }
        }
        if sub.touched != nil && (touched == nil || touched! < sub.touched!) {
            touched = sub.touched
        }
        if sub.deleted != nil {
            deleted = sub.deleted
        }
        if sub.acs != nil {
            if acs == nil {
                self.acs = Acs(from: sub.acs!)
                changed = true
            } else {
                changed = acs!.merge(from: sub.acs) || changed
            }
        }

        if getRead < sub.getRead {
            read = sub.getRead
            changed = true
        }
        if getRecv < sub.getRecv {
            recv = sub.getRecv
            changed = true
        }
        if getClear < sub.getClear {
            clear = sub.getClear
            changed = true
        }
        if getSeq < sub.getSeq {
            seq = sub.getSeq
            changed = true
        }
        if sub.priv != nil {
            priv = sub.priv
        }
        if sub.online != nil {
            online = sub.online
        }
        if (topic?.isEmpty ?? true) && !(sub.topic?.isEmpty ?? true) {
            topic = sub.topic
            changed = true
        }
        if sub.seen != nil {
            if seen == nil {
                seen = sub.seen
                changed = true
            } else {
                changed = seen!.merge(seen: sub.seen) || changed
            }
        }

        return changed
    }
    public func serializePub() -> String? {
        guard let p = pub else { return nil }
        return Tinode.serializeObject(p)
    }
    @discardableResult
    public func deserializePub(from data: String?) -> Bool {
        if let p: SP = Tinode.deserializeObject(from: data) {
            self.pub = p
            return true
        }
        return false
    }
    public func serializePriv() -> String? {
        guard let p = priv else { return nil }
        return Tinode.serializeObject(p)
    }
    @discardableResult
    public func deserializePriv(from data: String?) -> Bool {
        if let p: SR = Tinode.deserializeObject(from: data) {
            self.priv = p
            return true
        }
        return false
    }
    public func serializeTrusted() -> String? {
        guard let t = trusted else { return nil }
        return Tinode.serializeObject(t)
    }
    @discardableResult
    public func deserializeTrusted(from data: String?) -> Bool {
        if let t: TrustedType = Tinode.deserializeObject(from: data) {
            self.trusted = t
            return true
        }
        return false
    }
}
