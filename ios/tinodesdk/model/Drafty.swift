//
//  Drafty.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

class Style: Codable {
    var at: Int?
    var len: Int?
    var tp: String?
    var key: Int?
}

class Entity: Codable {
    var tp: String?
    var data: [String:JSONValue]?
}
/*
 TODO: add support for Drafty. For now, treat messages as raw strings.
class Drafty: Codable {
    var txt: String?
    var fmt: [Style]?
    var ent: [Entity]?
}
*/
typealias Drafty = String
