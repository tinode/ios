//
//  Subscription.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

struct LastSeen: Decodable {
    var when: Date?
    var ua: String?
}

// Messages may send subscriptions with different
// public and private types. We need to have a common type
// to handle subscriptions with all these types.
protocol SubscriptionProto: class, Decodable {
    var user: String? { get set }
    var updated: Date? { get set }
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
    func serializePub() -> String?
    @discardableResult
    func deserializePub(from data: String?) -> Bool
    
    static func createByName(name: String?) -> SubscriptionProto?
}

extension SubscriptionProto {
    static func createByName(name: String?) -> SubscriptionProto? {
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

class Subscription<SP: Codable, SR: Codable>: SubscriptionProto {
    var user: String?
    var updated: Date?
    var deleted: Date?
    var touched: Date?

    var acs: Acs?
    var read: Int? = 0
    var getRead: Int { get { return read ?? 0 } }
    var recv: Int? = 0
    var getRecv: Int { get { return recv ?? 0 } }
    var priv: SR?
    var online: Bool?

    var topic: String?
    var seq: Int? = 0
    var getSeq: Int { get { return seq ?? 0 } }
    var clear: Int? = 0
    var getClear: Int { get { return clear ?? 0 } }
    var pub: SP?
    var seen: LastSeen?
    var payload: Payload? = nil

    private enum CodingKeys : String, CodingKey {
        case user, updated, deleted, touched,
             acs, read, recv, priv = "private", online,
             topic, seq, clear, pub = "public", seen
    }

    func updateAccessMode(ac: AccessChange?) {
        if acs == nil {
            acs = Acs(from: nil as Acs?)
        }
        acs!.update(from: ac)
    }

    func merge(sub: Subscription<SP, SR>) -> Bool {
        var changed = 0
        if user == nil && !(sub.user?.isEmpty ?? true) {
            user = sub.user
            changed += 1
        }
        if sub.updated != nil && (updated == nil || updated! < sub.updated!) {
            updated = sub.updated
            if sub.pub != nil {
                pub = sub.pub
            }
            changed += 1
        } else if pub == nil && sub.pub != nil {
            pub = sub.pub
        }
        if sub.touched != nil && (touched == nil || touched! < sub.touched!) {
            touched = sub.touched
        }
        if sub.acs != nil {
            if acs == nil {
                self.acs = Acs(from: sub.acs!)
                changed += 1
            } else {
                changed += (acs!.merge(from: sub.acs) ? 1 : 0)
            }
        }
        
        return changed > 0
    }
    func serializePub() -> String? {
        guard let p = pub else { return nil }
        return Tinode.serializeObject(t: p)
    }
    @discardableResult
    func deserializePub(from data: String?) -> Bool {
        if let p: SP = Tinode.deserializeObject(from: data) {
            self.pub = p
            return true
        }
        return false
    }
}
