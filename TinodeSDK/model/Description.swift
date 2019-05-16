//
//  Description.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

// Dummy protocol.
// Messages may send descriptions with different
// public and private types. We need to have a common type
// to handle descriptions with all these types.
public protocol DescriptionProto: Codable {}

public typealias DescPublic = Any & Codable
public typealias DescPrivate = Any & Codable

public class Description<DP: Codable, DR: Codable>: DescriptionProto {
    var created: Date? = nil
    var updated: Date? = nil
    var touched: Date? = nil
    var defacs: Defacs? = nil
    var acs: Acs? = nil
    var seq: Int? = 0
    var getSeq: Int { get { return seq ?? 0 } }
    // Values reported by the current user as read and received
    var read: Int? = 0
    var getRead: Int { get { return read ?? 0 } }
    var recv: Int? = 0
    var getRecv: Int { get { return recv ?? 0 } }
    var clear: Int? = 0
    var getClear: Int { get { return clear ?? 0} }

    var pub: DP? = nil
    var priv: DR? = nil

    private enum CodingKeys : String, CodingKey {
        case created, updated, touched,
             defacs, acs, seq, read, recv, clear,
             pub = "public", priv = "private"
    }

    func merge(desc: Description) -> Bool {
        var changed = 0
        if created == nil && desc.created != nil {
            created = desc.created
            changed += 1
        }
        if desc.updated != nil && (updated == nil || updated! < desc.updated!) {
            updated = desc.updated
            changed += 1
        }
        if desc.touched != nil && (touched == nil || touched! < desc.touched!) {
            touched = desc.touched
            changed += 1
        }
        if desc.defacs != nil {
            if defacs == nil {
                defacs = desc.defacs
                changed += 1
            } else {
                changed += (defacs!.merge(defacs: desc.defacs!) ? 1 : 0)
            }
        }
        if desc.acs != nil {
            if acs == nil {
                acs = desc.acs
                changed += 1
            } else {
                changed += (acs!.merge(from: desc.acs) ? 1 : 0)
            }
        }
        if getSeq < desc.getSeq {
            seq = desc.getSeq
            changed += 1
        }
        if getRead < desc.getRead {
            read = desc.getRead
            changed += 1
        }
        if getRecv < desc.getRecv {
            recv = desc.getRecv
            changed += 1
        }
        if getClear < desc.getClear {
            clear = desc.getClear
            changed += 1
        }
        if desc.pub != nil {
            pub = desc.pub
        }
        if desc.priv != nil {
            priv = desc.priv
        }
        return changed > 0
    }

    // Merges subscription into a description.
    func merge<SP: Decodable, SR: Decodable>(sub: Subscription<SP, SR>) -> Bool {
        var changed = 0
        if sub.updated != nil && (updated == nil || updated! < sub.updated!) {
            updated = sub.updated
            changed += 1
        }
        if getSeq < sub.getSeq {
            seq = sub.getSeq
            changed += 1
        }
        if getRead < sub.getRead {
            read = sub.getRead
            changed += 1
        }
        if getRecv < sub.getRecv {
            recv = sub.getRecv
            changed += 1
        }
        if getClear < sub.getClear {
            clear = sub.getClear
            changed += 1
        }
        if sub.pub != nil {
            pub = (sub.pub as! DP)
            changed += 1
        }
        if sub.priv != nil {
            priv = sub.priv as? DR
            changed += 1
        }
        return changed > 0
    }
    func merge(desc: MetaSetDesc<DP, DR>) -> Bool {
        var changed = 0
        if let defacs = desc.defacs {
            if self.defacs == nil {
                self.defacs = defacs
                changed += 1
            } else {
                changed += self.defacs!.merge(defacs: defacs) ? 1 : 0
            }
        }
        if let pub = desc.pub {
            self.pub = pub
        }
        if let priv = desc.priv {
            self.priv = priv
        }
        return changed > 0
    }
}
