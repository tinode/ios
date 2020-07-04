//
//  Defacs.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

public class Defacs: Codable, Equatable {
    public var auth: AcsHelper?
    public var anon: AcsHelper?

    init(auth: String?, anon: String?) {
        if let auth = auth {
            setAuth(a: auth)
        }
        if let anon = anon {
            setAnon(a: anon)
        }
    }

    init(from acs: Defacs) {
        if let auth = acs.auth {
            self.auth = AcsHelper(ah: auth)
        }
        if let anon = acs.anon {
            self.anon = AcsHelper(ah: anon)
        }
    }
    private enum CodingKeys : String, CodingKey  {
        case auth, anon
    }
    required public init(from decoder: Decoder) throws {
        let container =  try decoder.container (keyedBy: CodingKeys.self)
        if let authStr = try? container.decode(String.self, forKey: .auth) {
            setAuth(a: authStr)
        }
        if let anonStr = try? container.decode(String.self, forKey: .anon) {
            setAnon(a: anonStr)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let auth = auth {
            try container.encode(auth.description, forKey: .auth)
        }
        if let anon = anon {
            try container.encode(anon.description, forKey: .anon)
        }
    }

    public func getAuth() -> String? {
        return auth != nil ? auth!.description : nil
    }
    func setAuth(a: String) {
        auth = AcsHelper(str: a)
    }

    public func getAnon() -> String? {
        return anon != nil ? anon!.description : nil
    }
    func setAnon(a: String) {
        anon = AcsHelper(str: a)
    }
    func merge(defacs: Defacs) -> Bool {
        var changed = 0
        if defacs.auth != nil {
            if auth == nil {
                auth = defacs.auth
                changed += 1
            } else {
                changed += (auth!.merge(with: defacs.auth) ? 1 : 0)
            }
        }
        if defacs.anon != nil {
            if anon == nil {
                anon = defacs.anon
                changed += 1
            } else {
                changed += (anon!.merge(with: defacs.anon) ? 1 : 0)
            }
        }
        return changed > 0
    }

    @discardableResult
    func update(auth: String?, anon: String?) -> Bool {
        var changed: Bool = false
        if let auth = auth {
            if self.auth == nil {
                self.auth = AcsHelper(a: AcsHelper.kModeNone)
            }
            changed = self.auth!.update(from: auth)
        }
        if let anon = anon {
            if self.anon == nil {
                self.anon = AcsHelper(a: AcsHelper.kModeNone)
            }
            changed = changed || self.anon!.update(from: anon)
        }
        return changed
    }

    public static func == (lhs: Defacs, rhs: Defacs) -> Bool {
        return lhs.anon == rhs.anon && lhs.auth == rhs.auth
    }

    public func serialize() -> String {
        return [self.auth?.description ?? "",
                self.anon?.description ?? ""].joined(separator: ",")
    }
    static public func deserialize(from data: String?) -> Defacs? {
        guard let parts = data?.components(separatedBy: ","), parts.count == 2 else {
            return nil
        }
        return Defacs(auth: parts[0], anon: parts[1])
    }
}
