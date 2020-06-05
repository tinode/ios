//
//  AcsHelper.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

public class AcsHelper: Codable, CustomStringConvertible, Equatable {
    enum AcsError: Error {
        case invalidValue
    }
    // J - join topic.
    public static let kModeJoin = 0x01
    // R - read broadcasts
    public static let kModeRead = 0x02
    // W - publish
    public static let kModeWrite = 0x04
    // P - receive presence notifications
    public static let kModePres = 0x08
    // A - approve requests
    public static let kModeApprove = 0x10
    // S - user can invite other people to join (S)
    public static let kModeShare = 0x20
    // D - user can hard-delete messages (D), only owner can completely delete
    public static let kModeDelete = 0x40
    // O - user is the owner (O) - full access
    public static let kModeOwner = 0x80
    // No access, requests to gain access are processed normally (N)
    public static let kModeNone = 0
    // Invalid mode to indicate an error
    public static let kModeInvalid = 0x100000

    private static let kModes = ["J", "R", "W", "P", "A", "S", "D", "O"]

    private var a: Int?

    public var description: String {
        guard let b = a else { return "" }
        return AcsHelper.encode(mode: b)
    }
    /// The value is neither nil nor Invalid. None is considered to be defined.
    public var isDefined: Bool {
        return (a ?? AcsHelper.kModeInvalid) != AcsHelper.kModeInvalid
    }
    public var isOwner: Bool {
        return ((a ?? 0) & AcsHelper.kModeOwner) != 0
    }
    public var isAdmin: Bool {
        return ((a ?? 0) & AcsHelper.kModeApprove) != 0
    }
    public var isManager: Bool {
        return isOwner || isAdmin
    }
    public var isSharer: Bool {
        return ((a ?? 0) & AcsHelper.kModeShare) != 0
    }
    public var isMuted: Bool {
        return ((a ?? 0) & AcsHelper.kModePres) == 0
    }
    public var isInvalid: Bool {
        return (a ?? 0) == AcsHelper.kModeInvalid
    }
    public var isJoiner: Bool {
        return ((a ?? 0) & AcsHelper.kModeJoin) != 0
    }
    public var isReader: Bool {
        return ((a ?? 0) & AcsHelper.kModeRead) != 0
    }
    public var isWriter: Bool {
        return ((a ?? 0) & AcsHelper.kModeWrite) != 0
    }
    public var isDeleter: Bool {
        return ((a ?? 0) & AcsHelper.kModeDelete) != 0
    }
    public var isNone: Bool {
        return (a ?? -1) == AcsHelper.kModeNone
    }
    public init(str: String?) {
        a = AcsHelper.decode(from: str)
    }
    public init(ah: AcsHelper?) {
        if ah != nil {
            a = ah!.a
        }
    }
    init(a: Int?) {
        self.a = a
    }
    public func hasPermissions(forMode mode: Int) -> Bool {
        guard !isInvalid else { return false }
        return (a! & mode) != 0
    }
    private static func decode(from modeStr: String?) -> Int {
        guard let mode = modeStr, mode.count > 0 else {
            return kModeInvalid
        }
        var m0 = kModeNone
        let modeUpper = mode.uppercased()
        for c in modeUpper {
            if let idx = kModes.firstIndex(of: String(c)) {
                m0 |= 1 << idx
            } else {
                return c == "N" ? kModeNone : kModeInvalid
            }
        }
        return m0
    }
    private static func encode(mode: Int) -> String {
        if mode == kModeInvalid {
            return ""
        }
        if mode == kModeNone {
            return "N"
        }

        var result: [String] = []
        for i in 0..<kModes.count {
            if ((mode >> i) & 1) != 0 {
                result.append(kModes[i])
            }
        }
        return result.joined()
    }

    // Same as split() but retains the separators ["+", "-"]: "+ABC-DEF" -> ["+ABC", "-DEF"]
    private static func tokenizeCommand(command str: String) -> [String] {
        var result: [String] = []
        var temp = ""
        for c in str {
            if c == "+" || c == "-" {
                if !temp.isEmpty {
                    result.append(temp)
                    // Clear temp.
                    temp.removeAll()
                }
            }
            temp.append(c)
        }
        if !temp.isEmpty {
            result.append(temp)
        }
        return result
    }

    @discardableResult
    public func update(from umode: String) -> Bool {
        let olda = a
        do {
            // Invalid value may be recived from the network. Invalid network data should not crash the client.
            try a = AcsHelper.update(original: a, updateWith: umode)
        } catch {
            Tinode.log.error("AcsHelper.update - failed to parse access mode: '%@' - %@",
                             umode, error.localizedDescription)
        }
        return a != olda
    }

    private static func update(original mode: Int?, updateWith command: String?) throws -> Int? {
        guard let command = command, command.count > 0 else {
            return mode
        }
        var result: Int
        let action = command.first //[command.startIndex]
        if action == "+" || action == "-" {
            result = mode ?? 0
            let parts = tokenizeCommand(command: command)
            for p in parts {
                // Skip command character and decode
                let m0 = decode(from: String(p.dropFirst(1)))
                if m0 == kModeInvalid {
                    throw AcsError.invalidValue
                }
                if m0 == kModeNone {
                    continue
                }
                if p.first == "+" { // p[p.startIndex]
                    result |= m0
                } else {
                    result &= ~m0
                }
            }
        } else {
            result = AcsHelper.decode(from: command)
            if result == kModeInvalid {
                throw AcsError.invalidValue
            }
        }
        return result
    }
    public func merge(with ah: AcsHelper?) -> Bool {
        guard ah != nil && self.a != nil && self.a! != AcsHelper.kModeInvalid else {
            return false
        }
        if let aha = ah!.a, aha != self.a {
            self.a = aha
            return true
        }
        return false
    }
    // Bitwise & operator.
    public static func and(a1: AcsHelper? , a2: AcsHelper?) -> AcsHelper? {
        guard let ah1 = a1, let ah2 = a2, !ah1.isInvalid, !ah2.isInvalid else { return nil }
        return AcsHelper(a: ah1.a! & ah2.a!)
    }
    // Bits present in a1 but missing in a2.
    public static func diff(a1: AcsHelper?, a2: AcsHelper?) -> AcsHelper? {
        guard let a1a = a1?.a, let a2a = a2?.a, !a1!.isInvalid, !a2!.isInvalid else { return nil }
        return AcsHelper(a: a1a & ~a2a)
    }
    public static func == (lhs: AcsHelper, rhs: AcsHelper) -> Bool {
        return lhs.a == rhs.a
    }
}
