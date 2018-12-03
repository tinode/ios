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

// Dummy protocol.
// Messages may send subscriptions with different
// public and private types. We need to have a common type
// to handle subscriptions with all these types.
protocol SubscriptionProto: Decodable {}

class Subscription<SP: Decodable, SR: Decodable>: SubscriptionProto {
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
}
