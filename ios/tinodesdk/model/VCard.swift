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
    let fn: String?
    let n: Name?
    let org: String?
    let title: String?
    // List of phone numbers associated with the contact.
    let tel: [Contact]?
    // List of contact's email addresses.
    let email: [Contact]?
    let impp: [Contact]?
    // Avatar photo.
    let photo: Photo?
}
