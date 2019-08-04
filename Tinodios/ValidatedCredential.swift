//
//  Validate.swift
//  Tinodios
//
//  Created by ztimc on 2018/12/26.
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import Contacts

enum ValidatedCredential {
    case email(_: String)
    case phoneNum(_: String)
    case URL(_: String)
    case IP(_: String)


    mutating func isValid() -> Bool {
        var predicateStr:String!
        var currObject:String!
        switch self {
        case let .email(str):
            predicateStr = "^([a-z0-9_\\.-]+)@([\\da-z\\.-]+)\\.([a-z\\.]{2,6})$"
            currObject = str
        case let .phoneNum(str):
            let e164 = CNPhoneNumber(stringValue: str).naiveE164
            if !e164.isEmpty {
                print("phone = \(e164)")
                self = .phoneNum(e164)
                return true
            } else {
                return false
            }
        case let .URL(str):
            predicateStr = "^(https?:\\/\\/)?([\\da-z\\.-]+)\\.([a-z\\.]{2,6})([\\/\\w \\.-]*)*\\/?$"
            currObject = str
        case let .IP(str):
            predicateStr = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
            currObject = str
        }

        let predicate =  NSPredicate(format: "SELF MATCHES %@" ,predicateStr)
        return predicate.evaluate(with: currObject)
    }

    static public func parse(from str: String?) -> ValidatedCredential? {
        guard let str = str else { return nil }
        var email = ValidatedCredential.email(str)
        if email.isValid() { return email }
        var phone = ValidatedCredential.phoneNum(str)
        if phone.isValid() { return phone }
        var url = ValidatedCredential.URL(str)
        if url.isValid() { return url }
        var ip = ValidatedCredential.IP(str)
        if ip.isValid() { return ip }
        return nil
    }
}
