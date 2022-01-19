//
//  Description.swift
//  ios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import Foundation

// Dummy protocol.
// Messages may send descriptions with different
// public and private types. We need to have a common type
// to handle descriptions with all these types.
public protocol DescriptionProto: Codable {}

public class Description<DP: Codable & Mergeable, DR: Codable & Mergeable>: DescriptionProto {
    var created: Date?
    var updated: Date?
    var touched: Date?
    var defacs: Defacs?
    var acs: Acs?
    var seq: Int? = 0
    var getSeq: Int { return seq ?? 0 }
    // Values reported by the current user as read and received
    var read: Int? = 0
    var getRead: Int { return read ?? 0 }
    var recv: Int? = 0
    var getRecv: Int { return recv ?? 0 }
    var clear: Int? = 0
    var getClear: Int { return clear ?? 0 }

    var pub: DP?
    var priv: DR?
    var trusted: TrustedType?

    var seen: LastSeen?

    private enum CodingKeys: String, CodingKey {
        case created, updated, touched,
             defacs, acs, seq, read, recv, clear,
             pub = "public", priv = "private", trusted, seen
    }

    private func mergePub(with another: DP) -> Bool {
        guard self.pub != nil else {
            self.pub = another
            return true
        }
        return self.pub!.merge(with: another)
    }

    private func mergePriv(with another: DR) -> Bool {
        guard self.priv != nil else {
            self.priv = another
            return true
        }
        return self.priv!.merge(with: another)
    }

    private func mergeTrusted(with another: TrustedType) -> Bool {
        guard self.trusted != nil else {
            self.trusted = another
            return true
        }
        return self.trusted!.merge(with: another)
    }

    func merge(desc: Description<DP, DR>) -> Bool {
        var changed = false
        if created == nil && desc.created != nil {
            created = desc.created
            changed = true
        }
        if desc.updated != nil && (updated == nil || updated! < desc.updated!) {
            updated = desc.updated
            changed = true
        }
        if desc.touched != nil && (touched == nil || touched! < desc.touched!) {
            touched = desc.touched
            changed = true
        }
        if desc.defacs != nil {
            if defacs == nil {
                defacs = desc.defacs
                changed = true
            } else {
                changed = defacs!.merge(defacs: desc.defacs!) || changed
            }
        }
        if desc.acs != nil {
            if acs == nil {
                acs = desc.acs
                changed = true
            } else {
                changed = acs!.merge(from: desc.acs) || changed
            }
        }
        if getSeq < desc.getSeq {
            seq = desc.getSeq
            changed = true
        }
        if getRead < desc.getRead {
            read = desc.getRead
            changed = true
        }
        if getRecv < desc.getRecv {
            recv = desc.getRecv
            changed = true
        }
        if getClear < desc.getClear {
            clear = desc.getClear
            changed = true
        }
        if let spub = desc.pub {
            changed = mergePub(with: spub) || changed
        }

        if let spriv = desc.priv {
            changed = mergePriv(with: spriv) || changed
        }

        if let trusted = desc.trusted {
            changed = mergeTrusted(with: trusted) || changed
        }

        if let dseen = desc.seen {
            if seen == nil {
                seen = dseen
                changed = true
            } else {
                changed = seen!.merge(seen: dseen) || changed
            }
        }
        return changed
    }

    // Merges subscription into a description.
    func merge<SP: Decodable, SR: Decodable>(sub: Subscription<SP, SR>) -> Bool {
        var changed = false
        if sub.updated != nil && (updated == nil || updated! < sub.updated!) {
            updated = sub.updated
            changed = true
        }
        if sub.touched != nil && (touched == nil || touched! < sub.touched!) {
            touched = sub.touched
            changed = true
        }
        if let newAcs = sub.acs {
            if acs == nil {
                acs = newAcs
                changed = true
            } else {
                changed = acs!.merge(from: newAcs) || changed
            }
        }
        if getSeq < sub.getSeq {
            seq = sub.getSeq
            changed = true
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
        if sub.pub != nil {
            changed = mergePub(with: sub.pub as! DP) || changed
        }
        if sub.priv != nil {
            changed = mergePriv(with: sub.priv as! DR) || changed
        }
        if sub.trusted != nil {
            changed = mergeTrusted(with: sub.trusted!) || changed
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
    func merge(desc: MetaSetDesc<DP, DR>) -> Bool {
        var changed = false
        if let defacs = desc.defacs {
            if self.defacs == nil {
                self.defacs = defacs
                changed = true
            } else {
                changed = self.defacs!.merge(defacs: defacs)
            }
        }
        if let pub = desc.pub {
            changed = mergePub(with: pub) || changed
        }
        if let priv = desc.priv {
            changed = mergePriv(with: priv) || changed
        }
        if let trusted = desc.trusted {
            changed = mergeTrusted(with: trusted) || changed
        }
        return changed
    }
}
