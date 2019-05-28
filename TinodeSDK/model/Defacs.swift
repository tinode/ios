//
//  Defacs.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

public class Defacs: Codable {
    var auth: AcsHelper?
    var anon: AcsHelper?
    
    init(auth: String, anon: String) {
        setAuth(a: auth)
        setAnon(a: anon)
    }
    private enum CodingKeys : String, CodingKey  {
        case auth, anon
    }
    required public init (from decoder: Decoder) throws {
        let container =  try decoder.container (keyedBy: CodingKeys.self)
        if let authStr = try? container.decode(String.self, forKey: .auth) {
            setAuth(a: authStr)
        }
        if let anonStr = try? container.decode(String.self, forKey: .anon) {
            setAnon(a: anonStr)
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
