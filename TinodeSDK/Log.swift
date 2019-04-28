//
//  Logging.swift
//  TinodeSDK
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import os.log

enum LogType {
    case debug
    case info
    case error
    case fault
}

class Log {
    private var osLog: OSLog?
    let subsystem: String
    let category: String
    private static let `default` = Log(category: "default")
    init(subsystem: String = Bundle.main.bundleIdentifier ?? "", category: String = "") {
        if #available(iOS 10.0, *) {
            let osLog = OSLog(subsystem: subsystem, category: category)
            self.osLog = osLog
        }
        self.subsystem = subsystem
        self.category = category
    }
    func log(type: LogType, message: StaticString, _ args: CVarArg...) {
        if #available(iOS 10.0, *) {
            guard let osLog = osLog else { return }
            let logType: OSLogType
            switch type {
            case .debug:
                logType = .debug
            case .error:
                logType = .error
            case .fault:
                logType = .fault
            case .info:
                logType = .info
            }
            os_log(message, log: osLog, type: logType, args)
        } else {
            NSLog(message.description, args)
        }
    }
    func log(type: LogType, message: StaticString) {
        log(type: type, message: message, "")
    }
    func debug(_ message: StaticString, _ args: CVarArg...) {
        log(type: .debug, message: message, args)
    }
    static func debug(_ message: StaticString, _ args: CVarArg...) {
        Log.default.debug(message, args)
    }
    func info(_ message: StaticString, _ args: CVarArg...) {
        log(type: .info, message: message, args)
    }
    static func info(_ message: StaticString, _ args: CVarArg...) {
        Log.default.info(message, args)
    }
    func error(_ message: StaticString, _ args: CVarArg...) {
        log(type: .error, message: message, args)
    }
    static func error(_ message: StaticString, _ args: CVarArg...) {
        Log.default.error(message, args)
    }
    func fault(_ message: StaticString, _ args: CVarArg...) {
        log(type: .fault, message: message, args)
    }
    static func fault(_ message: StaticString, _ args: CVarArg...) {
        Log.default.fault(message, args)
    }
}
