//
//  AuthScheme.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

struct AuthScheme {
    enum AuthSchemeError: Error {
        case invalidParams(String)
    }
    static let kLoginBasic = "basic"
    static let kLoginToken = "token"
    static let kLoginReset = "reset"

    let scheme: String
    let secret: String

    init(scheme: String, secret: String) {
        self.scheme = scheme
        self.secret = secret
    }

    static func parse(from str: String?) throws -> AuthScheme? {
        if let data = str {
            let parts = data.split(separator: ":")
            if parts.count == 2 {
                let scheme = String(parts[0])
                if scheme == kLoginBasic || scheme == kLoginToken {
                    return AuthScheme(scheme: scheme, secret: String(parts[1]))
                }
            } else {
                throw AuthSchemeError.invalidParams("Invalid param string \(data)")
            }
        }
        return nil
    }

    static func encodeBasicToken(uname: String, password: String) throws -> String {
        guard !uname.contains(":") else {
            throw AuthSchemeError.invalidParams("invalid user name: \(uname)")
        }
        return (uname + ":" + password).toBase64()!
    }

    static func encodeResetToken(scheme: String, method: String, value: String) throws -> String {
        guard !scheme.contains(":") && !method.contains(":") else {
            throw AuthSchemeError.invalidParams("invalid parameter")
        }
        return "\(scheme):\(method):\(value)".toBase64()!
    }

    static func decodeBasicToken(token: String) throws -> [String] {
        guard let basicToken = token.fromBase64() else {
            throw AuthSchemeError.invalidParams(
                "Failed to decode auth token from base64: \(token)")
        }

        let parts = basicToken.split(separator: ":")
        if parts.count != 2 || parts[0].isEmpty {
            throw AuthSchemeError.invalidParams(
                "Invalid basic token string: \(basicToken)")
        }
        return [String(parts[0]), String(parts[1])]
    }

    static func basicInstance(login: String, password: String) throws -> AuthScheme {
        return AuthScheme(scheme: kLoginBasic,
                          secret: try encodeBasicToken(uname: login, password: password))
    }

    static func tokenInstance(secret: String) -> AuthScheme {
        return AuthScheme(scheme: kLoginToken, secret: secret)
    }
}

extension String {
    func fromBase64() -> String? {
        guard let data = Data(base64Encoded: self,
                              options: Data.Base64DecodingOptions(
                                rawValue: 0)) else {
            return nil
        }
        return String(data: data as Data, encoding: String.Encoding.utf8)
    }
    func toBase64() -> String? {
        guard let data = self.data(using: String.Encoding.utf8) else {
            return nil
        }
        return data.base64EncodedString(
            options: Data.Base64EncodingOptions(rawValue: 0))
    }
}
