//
//  User.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

public protocol UserProto: class {
    var updated: Date? { get set }
    var uid: String? { get set }
    var payload: Payload? { get set }

    func serializePub() -> String?
    static func createFromPublicData(uid: String?, updated: Date?, data: String?) -> UserProto?
}

extension UserProto {
    public static func createFromPublicData(uid: String?, updated: Date?, data: String?) -> UserProto? {
        guard let data = data else { return nil }
        if let p: VCard = Tinode.deserializeObject(from: data) {
            return User(uid: uid, updated: updated, pub: p)
        }
        if let p: String = Tinode.deserializeObject(from: data) {
            return User(uid: uid, updated: updated, pub: p)
        }
        return nil
    }
}

public typealias DefaultUser = User<VCard>

public class User<P: Codable>: UserProto {
    enum UserError : Error {
        case invalidUser(String)
    }
    public var updated: Date?
    public var uid: String?
    public var pub: P?
    public var payload: Payload? = nil

    public init(uid: String?, updated: Date?, pub: P?) {
        self.uid = uid
        self.updated = updated
        self.pub = pub
    }
    public init<R: Decodable>(uid: String?, desc: Description<P, R>) {
        self.uid = uid
        self.updated = desc.updated
        self.pub = desc.pub
    }
    public init<R: Decodable>(sub: Subscription<P, R>) throws {
        if let uid = sub.user, !uid.isEmpty {
            self.uid = uid
            self.updated = sub.updated
            self.pub = sub.pub
        } else {
            throw UserError.invalidUser("Invalid subscription param: missing uid")
        }
    }
    public func serializePub() -> String? {
        guard let p = pub else { return nil }
        return Tinode.serializeObject(p)
    }
    func merge(from user: User<P>) -> Bool {
        var changed = false
        if user.updated != nil && (self.updated == nil || self.updated! < user.updated!) {
            self.updated = user.updated
            if user.pub != nil {
                self.pub = user.pub
            }
            changed = true
        } else if self.pub == nil && user.pub != nil {
            self.pub = user.pub
            changed = true
        }
        return changed
    }

    public func merge<DR: Decodable>(from desc: Description<P, DR>) -> Bool {
        var changed = false
        if desc.updated != nil && (self.updated == nil || self.updated! < desc.updated!) {
            self.updated = desc.updated
            if desc.pub != nil {
                self.pub = desc.pub
            }
            changed = true
        } else if self.pub == nil && desc.pub != nil {
            self.pub = desc.pub
            changed = true
        }
        return changed
    }

    func merge<DR: Decodable>(from sub: Subscription<P, DR>) -> Bool {
        var changed = false
        if sub.updated != nil && (self.updated == nil || self.updated! < sub.updated!) {
            self.updated = sub.updated
            if sub.pub != nil {
                self.pub = sub.pub
            }
            changed = true
        } else if self.pub == nil && sub.pub != nil {
            self.pub = sub.pub
            changed = true
        }
        return changed
    }
}
