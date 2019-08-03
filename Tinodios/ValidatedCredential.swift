//
//  Validate.swift
//  Tinodios
//
//  Created by ztimc on 2018/12/26.
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation


enum ValidatedCredential {
    case email(_: String)
    case phoneNum(_: String)
    case URL(_: String)
    case IP(_: String)


    var isRight: Bool {
        var predicateStr:String!
        var currObject:String!
        switch self {
        case let .email(str):
            predicateStr = "^([a-z0-9_\\.-]+)@([\\da-z\\.-]+)\\.([a-z\\.]{2,6})$"
            currObject = str
        case let .phoneNum(str):
            predicateStr = "^((13[0-9])|(15[^4,\\D]) |(17[0,0-9])|(18[0,0-9]))\\d{8}$"
            currObject = str
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
        let email = ValidatedCredential.email(str)
        if email.isRight { return email }
        let phone = ValidatedCredential.phoneNum(str)
        if phone.isRight { return phone }
        let url = ValidatedCredential.URL(str)
        if url.isRight { return url }
        let ip = ValidatedCredential.IP(str)
        if ip.isRight { return ip }
        return nil
    }
}
