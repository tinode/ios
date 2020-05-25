//
//  RFC3339Format.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

// Date extensions.
// From: https://stackoverflow.com/questions/46458487/how-to-convert-a-date-string-with-optional-fractional-seconds-using-codable-in-s
extension Formatter {
    public static let rfc3339: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSS'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    public static let rfc3339short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

extension JSONDecoder.DateDecodingStrategy {
    static let customRFC3339 = custom { decoder throws -> Date in
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if let date = Formatter.rfc3339.date(from: string) {
            return date
        }
        if let date = Formatter.rfc3339short.date(from: string) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "Invalid date: \(string)")
    }
}
extension JSONEncoder.DateEncodingStrategy {
    static let customRFC3339 = custom { date, encoder throws in
        var container = encoder.singleValueContainer()
        try container.encode(Formatter.rfc3339.string(from: date))
    }
}
