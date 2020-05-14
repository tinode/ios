//
//  Acs.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

public class Acs: Codable, CustomStringConvertible, Equatable {
    public enum Side {
        case mode, want, given
    }
    public var given: AcsHelper?
    public var want: AcsHelper?
    public var mode: AcsHelper?

    public var description: String {
        return "w: '\(want?.description ?? "")', g: '\(given?.description ?? "")', m: '\(mode?.description ?? "")'"
    }

    /// The value is neither nil nor Invalid. None is considered to be defined.
    public var isModeDefined: Bool {
        return mode?.isDefined ?? false
    }
    public var isManager: Bool {
        return mode?.isManager ?? false
    }
    public var isOwner: Bool {
        return mode?.isOwner ?? false
    }
    public var isAdmin: Bool {
        return mode?.isAdmin ?? false
    }
    public var isSharer: Bool {
        return mode?.isSharer ?? false
    }
    public var isMuted: Bool {
        return mode?.isMuted ?? false
    }
    public var isInvalid: Bool {
        return mode?.isInvalid ?? false
    }
    public var isJoiner: Bool {
        return mode?.isJoiner ?? false
    }
    public var isWriter: Bool {
        return mode?.isWriter ?? false
    }
    public var isReader: Bool {
        return mode?.isReader ?? false
    }
    public var isDeleter: Bool {
        return mode?.isDeleter ?? false
    }
    public var isNone: Bool {
        return mode?.isNone ?? false
    }

    public var missing: AcsHelper? {
        return AcsHelper.diff(a1: self.want, a2: self.given)
    }
    public var excessive: AcsHelper? {
        return AcsHelper.diff(a1: self.given, a2: self.want)
    }
    public var isNoneGiven: Bool {
        return given?.isNone ?? false
    }
    public var isNoneWant: Bool {
        return want?.isNone ?? false
    }
    public var modeString: String {
        return mode?.description ?? ""
    }
    public var wantString: String {
        return want?.description ?? ""
    }
    public var givenString: String {
        return given?.description ?? ""
    }
    private enum CodingKeys : String, CodingKey  {
        case given, want, mode
    }
    private func assign(given: String?, want: String?, mode: String?) {
        self.given = AcsHelper(str: given)
        self.want = AcsHelper(str: want)
        self.mode = AcsHelper(str: mode)
    }
    init() {
    }
    init(given: String?, want: String?, mode: String?) {
        self.assign(given: given, want: want, mode: mode)
    }
    public init(from am: Acs?) {
        if (am != nil) {
            given = AcsHelper(ah: am!.given)
            want = AcsHelper(ah: am!.want)
            mode = AcsHelper(ah: am!.mode)
        }
    }
    init(from dict: [String:String]?) {
        if let d = dict {
            self.assign(given: d["given"], want: d["want"], mode: d["mode"])
        }
    }
    required public init (from decoder: Decoder) throws {
        let container =  try decoder.container (keyedBy: CodingKeys.self)
        if let givenStr = try? container.decode(String.self, forKey: .given) {
            self.given = AcsHelper(str: givenStr)
        }
        if let wantStr = try? container.decode(String.self, forKey: .want) {
            self.want = AcsHelper(str: wantStr)
        }
        if let modeStr = try? container.decode(String.self, forKey: .mode) {
            self.mode = AcsHelper(str: modeStr)
        }
    }
    public func isJoiner(for side: Acs.Side) -> Bool {
        switch side {
        case .mode: return mode?.isJoiner ?? false
        case .want: return want?.isJoiner ?? false
        case .given: return given?.isJoiner ?? false
        }
    }
    @discardableResult
    func merge(from am: Acs?) -> Bool {
        var changed = 0
        if let am0 = am, self != am0 {
            if let g = am0.given {
                if given == nil {
                    given = AcsHelper(a: AcsHelper.kModeNone)
                }
                changed += (given!.merge(with: g) ? 1 : 0)
            }
            if let w = am0.want {
                if want == nil {
                    want = AcsHelper(a: AcsHelper.kModeNone)
                }
                changed += (want!.merge(with: w) ? 1 : 0)
            }
            if let m = am0.mode {
                if mode == nil {
                    mode = AcsHelper(a: AcsHelper.kModeNone)
                }
                changed += (mode!.merge(with: m) ? 1 : 0)
            } else {
                if let m2 = AcsHelper.and(a1: want, a2: given) {
                    changed += m2 == mode ? 0 : 1
                    mode = m2
                }
            }
        }
        return changed > 0
    }
    @discardableResult
    func update(from ac: AccessChange?) -> Bool {
        var changed = 0
        if let ac = ac {
            if let agiven = ac.given {
                if given != nil {
                    changed += given!.update(from: agiven) ? 1 : 0
                } else {
                    given = AcsHelper(str: agiven)
                    changed += given!.isDefined ? 1 : 0
                }
            }
            if let awant = ac.want {
                if want != nil {
                    changed += want!.update(from: awant) ? 1 : 0
                } else {
                    want = AcsHelper(str: awant)
                    changed += want!.isDefined ? 1 : 0
                }
            }
            if changed > 0 {
                if let m2 = AcsHelper.and(a1: want, a2: given) {
                    changed += m2 == mode ? 1 : 0
                    mode = m2
                }
            }
        }
        return changed > 0
    }

    /// Convert access mode into a string "MODE,WANT,GIVEN" like "JRWPA,JRWPA,JRWPA".
    public func serialize() -> String {
        return [self.mode?.description ?? "",
                self.want?.description ?? "",
                self.given?.description ?? ""].joined(separator: ",")
    }
    static public func deserialize(from data: String?) -> Acs? {
        guard let parts = data?.components(separatedBy: ","), parts.count == 3 else {
            return nil
        }
        return Acs(given: parts[2], want: parts[1], mode: parts[0])
    }
    public static func == (lhs: Acs, rhs: Acs) -> Bool {
        return lhs.mode == rhs.mode && lhs.want == rhs.want && lhs.given == rhs.mode
    }
}
