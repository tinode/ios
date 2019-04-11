//
//  VCard.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

public class Photo: Codable {
    public let type: String?
    // Byte array.
    public let data: String?
}

public class Contact: Codable {
    let type: String?
    let uri: String?
}

public class Name: Codable {
    let surname: String?
    let given: String?
    let additional: String?
    let prefix: String?
    let suffix: String?
}

public class VCard: Codable {
    public var fn: String?
    public var n: Name?
    public var org: String?
    public var title: String?
    // List of phone numbers associated with the contact.
    public var tel: [Contact]?
    // List of contact's email addresses.
    public var email: [Contact]?
    public var impp: [Contact]?
    // Avatar photo.
    public var photo: Photo?
    
    public init(fn: String?, avatar: Photo?) {
        self.fn = fn
        self.photo = avatar
    }
}
