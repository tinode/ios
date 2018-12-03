//
//  AcsHelper.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

class AcsHelper: Codable, Equatable {
    enum AcsError: Error {
        case invalidValue
    }
    // J - join topic.
    private static let kModeJoin = 0x01
    // R - read broadcasts
    private static let kModeRead = 0x02
    // W - publish
    private static let kModeWrite = 0x04
    // P - receive presence notifications
    private static let kModePres = 0x08
    // A - approve requests
    private static let kModeApprove = 0x10
    // S - user can invite other people to join (S)
    private static let kModeShare = 0x20
    // D - user can hard-delete messages (D), only owner can completely delete
    private static let kModeDelete = 0x40
    // O - user is the owner (O) - full access
    private static let kModeOwner = 0x80
    // No access, requests to gain access are processed normally (N)
    private static let kModeNone = 0
    // Invalid mode to indicate an error
    private static let kModeInvalid = 0x100000
    
    private static let kModes = ["J", "R", "W", "P", "A", "S", "D", "O"]
    
    private var a: Int?

    var description: String {
        guard a != nil else {
            return ""
        }
        return AcsHelper.encode(mode: a!)!
    }
    var isDefined: Bool {
        get {
            guard let b = a else {
                return false
            }
            return b != AcsHelper.kModeNone && b != AcsHelper.kModeInvalid
        }
    }
    init(str: String?) {
        a = AcsHelper.decode(from: str)
    }
    init(ah: AcsHelper?) {
        if ah != nil {
            a = ah!.a
        }
    }
    init(a: Int?) {
        self.a = a
    }
    public func isInvalid() -> Bool {
        return (a ?? 0) == AcsHelper.kModeInvalid
    }
    private static func decode(from modeStr: String?) -> Int? {
        guard let mode = modeStr, mode.count > 0 else {
            return nil
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
    private static func encode(mode: Int) -> String? {
        if mode == kModeInvalid {
            return nil
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
    // Same as split() but retains the separators ["+", "-"].
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
                result.append(String(c))
            } else {
                temp.append(c)
            }
        }
        if !temp.isEmpty {
            result.append(temp)
        }
        return result
    }
    public func update(from umode: String) -> Bool {
        let olda = a
        a = try! AcsHelper.update(original: a, updateWith: umode)
        return a != olda
    }
    private static func update(original mode: Int?, updateWith command: String?) throws -> Int? {
        guard let command = command, command.count > 0 else {
            return mode
        }
        var m0: Int
        var result: Int
        let action = command[command.startIndex]
        if action == "+" || action == "-" {
            result = mode ?? 0
            let parts = tokenizeCommand(command: command)
            let n = parts.count
            var i = 0
            while i < n {
                let p0 = parts[i]
                let action = p0[p0.startIndex]
                i += 1
                if i < n {
                    m0 = decode(from: parts[i])!
                } else {
                    break
                }
                if m0 == kModeInvalid {
                    throw AcsError.invalidValue
                }
                if m0 == kModeNone {
                    continue
                }
                if action == "+" {
                    result |= m0
                } else {
                    result &= ~m0
                }
            }
        } else {
            result = AcsHelper.decode(from: command)!
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
    public static func and(a1: AcsHelper? , a2: AcsHelper?) -> AcsHelper? {
        if let ah1 = a1, let ah2 = a2, !ah1.isInvalid(), !ah2.isInvalid() {
            return AcsHelper(a: ah1.a! & ah2.a!)
        }
        return nil
    }
    static func == (lhs: AcsHelper, rhs: AcsHelper) -> Bool {
        return lhs.a == rhs.a
    }
}
