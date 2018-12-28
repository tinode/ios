//
//  VCard.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

class Photo: Codable {
    let type: String?
    // Byte array.
    let data: String?
}

class Contact: Codable {
    let type: String?
    let uri: String?
}

class Name: Codable {
    let surname: String?
    let given: String?
    let additional: String?
    let prefix: String?
    let suffix: String?
}

class VCard: Codable {
    var fn: String?
    var n: Name?
    var org: String?
    var title: String?
    // List of phone numbers associated with the contact.
    var tel: [Contact]?
    // List of contact's email addresses.
    var email: [Contact]?
    var impp: [Contact]?
    // Avatar photo.
    var photo: Photo?
    
    init(fn: String?, avatar: Photo?) {
        self.fn = fn
        self.photo = avatar
    }
}
