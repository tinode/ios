//
//  Connection.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import SwiftWebSocket

public class Connection {
    private class ExpBackoffSteps {
        private let kBaseSleepMs = 500
        private let kMaxShift = 11
        private var attempt: Int = 0

        func getNextDelay() -> Int {
            if attempt > kMaxShift {
                attempt = kMaxShift
            }
            let half = UInt32(kBaseSleepMs * (1 << attempt))
            let delay = half + arc4random_uniform(half)
            attempt += 1
            return Int(delay)
        }
        func reset() {
            attempt = 0
        }
    }
    fileprivate let kConnectionTimeout = 3000
    
    var isConnected: Bool {
        get {
            if let conn = webSocketConnection, conn.readyState == .open {
                return true
            }
            return false
        }
    }
    
    private var webSocketConnection: WebSocket?
    private var connectionListener: ConnectionListener?
    private var endpoint: URL
    private var apiKey: String
    private var useTLS = false
    private var connectQueue = DispatchQueue(label: "co.tinode.connection")
    private var autoreconnect: Bool = false
    private var reconnecting: Bool = false
    private var backoffSteps = ExpBackoffSteps()
    
    init(open url: URL, with apiKey: String, notify listener: ConnectionListener?) {
        self.apiKey = apiKey
        // TODO: apply necessary URL modifications.
        self.endpoint = url
        self.connectionListener = listener
        if url.scheme == "wss" || url.scheme == "https" {
            self.useTLS = true
        }
        self.webSocketConnection = WebSocket()
        // Do not run on the UI thread.
        // TODO: figure out if we need to set up a separate queue.
        self.webSocketConnection!.eventQueue = DispatchQueue.global(qos: .userInteractive)
        webSocketConnection!.event.open = {
            print("opened")
            self.backoffSteps.reset()
            self.reconnecting = false
            self.connectionListener?.onConnect()
        }
        webSocketConnection!.event.error = { error in
            print("error \(error)")
            self.connectionListener?.onError(error: error)
        }
        webSocketConnection!.event.message = { message in
            print("message")
            self.connectionListener?.onMessage(with: message as! String)
        }
        webSocketConnection!.event.close = { code, reason, clean in
            print("connection closed \(code) \(reason) \(clean)")
            self.connectionListener?.onDisconnect(isServerOriginated: clean, code: code, reason: reason)
            guard !self.reconnecting else {
                return
            }
            self.reconnecting = self.autoreconnect
            if self.autoreconnect {
                self.connectWithBackoffAsync()
            }
        }
    }

    private func createUrlRequest() throws -> URLRequest {
        var components = URLComponents()
        components.scheme = self.endpoint.scheme!
        components.host = self.endpoint.host!
        components.port = self.endpoint.port!
        components.path = "/v0/channels"
        var request = URLRequest(url: components.url!)
        request.addValue(apiKey, forHTTPHeaderField: "X-Tinode-APIKey")
        return request
    }
    
    private func openConnection(with urlRequest: URLRequest) {
        self.webSocketConnection?.open(request: urlRequest)
    }
    private func connectSocket() {
        let request = try! createUrlRequest()
        self.openConnection(with: request)
    }
    private func connectWithBackoffAsync() {
        let delay = Double(self.backoffSteps.getNextDelay()) / 1000
        print("will reconnect run after \(delay) sec")
        self.connectQueue.asyncAfter(
            deadline: .now() + delay,
            execute: {
                print("reconnecting now")
                self.connectSocket()
                if !self.isConnected {
                    self.reconnecting = false
                    return
                }
                self.connectWithBackoffAsync()
        })
    }
    func connect(reconnectAutomatically: Bool = true) throws -> Bool {
        self.autoreconnect = reconnectAutomatically
        if self.autoreconnect && self.reconnecting {
            // If we are trying to reconnect, do it now.
            // TODO: cancel any tasks in connectQueue and try to connect immediately.
        } else {
            connectSocket()
        }
        return true
    }
    func disconnect() {
        webSocketConnection?.close()
        // TODO: handle autoreconnect.
        if autoreconnect {
            autoreconnect = false
            // TODO: cancel all work in the reconnect queue.
        }
    }
    
    func send(payload data: Data) -> Void {
        webSocketConnection?.send(data: data)
    }
    
}

protocol ConnectionListener {
    func onConnect() -> Void
    func onMessage(with message: String) -> Void
    func onDisconnect(isServerOriginated: Bool, code: Int, reason: String) -> Void
    func onError(error: Error) -> Void
}
