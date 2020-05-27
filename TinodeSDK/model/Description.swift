//
//  Description.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

// Dummy protocol.
// Messages may send descriptions with different
// public and private types. We need to have a common type
// to handle descriptions with all these types.
public protocol DescriptionProto: Codable {}

public class Description<DP: Codable & Mergeable, DR: Codable & Mergeable>: DescriptionProto {
    var created: Date? = nil
    var updated: Date? = nil
    var touched: Date? = nil
    var defacs: Defacs? = nil
    var acs: Acs? = nil
    var seq: Int? = 0
    var getSeq: Int { return seq ?? 0 }
    // Values reported by the current user as read and received
    var read: Int? = 0
    var getRead: Int { return read ?? 0 }
    var recv: Int? = 0
    var getRecv: Int { return recv ?? 0 }
    var clear: Int? = 0
    var getClear: Int { return clear ?? 0 }

    var pub: DP? = nil
    var priv: DR? = nil

    private enum CodingKeys : String, CodingKey {
        case created, updated, touched,
             defacs, acs, seq, read, recv, clear,
             pub = "public", priv = "private"
    }

    private func mergePub(with another: DP) -> Int {
        guard self.pub != nil else {
            self.pub = another
            return 1
        }
        return self.pub!.merge(with: another)
    }

    private func mergePriv(with another: DR) -> Int {
        guard self.priv != nil else {
            self.priv = another
            return 1
        }
        return self.priv!.merge(with: another)
    }

    func merge(desc: Description<DP, DR>) -> Bool {
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
        if let spub = desc.pub {
            if mergePub(with: spub) > 0 {
                changed += 1
            }
        }
        if let spriv = desc.priv {
            if mergePriv(with: spriv) > 0 {
                changed += 1
            }
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
        if sub.touched != nil && (touched == nil || touched! < sub.touched!) {
            touched = sub.touched
            changed += 1
        }
        if let newAcs = sub.acs {
            if acs == nil {
                acs = newAcs
                changed += 1
            } else {
                changed += acs!.merge(from: newAcs) ? 1 : 0
            }
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
            let spub = sub.pub as! DP
            if mergePub(with: spub) > 0 {
                changed += 1
            }
        }
        if sub.priv != nil {
            let spriv = sub.priv as! DR
            if mergePriv(with: spriv) > 0 {
                changed += 1
            }
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
            if mergePub(with: pub) > 0 {
                changed += 1
            }
        }
        if let priv = desc.priv {
            if mergePriv(with: priv) > 0 {
                changed += 1
            }
        }
        return changed > 0
    }
}
