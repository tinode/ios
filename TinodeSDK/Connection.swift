//
//  Connection.swift
//  TinodeSDK
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import Foundation

public class Connection: WebSocketConnectionDelegate {
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

    // Connection timeout in seconds.
    fileprivate let kConnectionTimeout: TimeInterval = 3.0

    var isConnected: Bool {
        guard let conn = webSocketConnection else { return false }
        return conn.state == .open
    }

    var isWaitingToConnect: Bool {
        guard let conn = webSocketConnection else { return false }
        return conn.state == .connecting
    }

    private var webSocketConnection: WebSocket?
    private var connectionListener: ConnectionListener?
    private var endpointComponenets: URLComponents
    private var apiKey: String
    private var useTLS = false
    private var connectQueue = DispatchQueue(label: "co.tinode.connection")
    private var autoreconnect: Bool = false
    private var reconnecting: Bool = false
    private var backoffSteps = ExpBackoffSteps()
    private var reconnectClosure: DispatchWorkItem?
    // Opaque parameter passed to onConnect. Used once then discarded.
    private var param: Any?

    init(open url: URL, with apiKey: String, notify listener: ConnectionListener?) {
        self.apiKey = apiKey
        // TODO: apply necessary URL modifications.
        self.endpointComponenets = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        self.connectionListener = listener
        if let scheme = endpointComponenets.scheme, scheme == "wss" || scheme == "https" {
            endpointComponenets.scheme = "wss"
            useTLS = true
        } else {
            endpointComponenets.scheme = "ws"
        }
        if endpointComponenets.port == nil {
            endpointComponenets.port = useTLS ? 443 : 80
        }
        self.webSocketConnection = WebSocket(timeout: kConnectionTimeout, delegate: self)
        maybeInitReconnectClosure()
    }

    func onConnected(connection: WebSocket) {
        self.backoffSteps.reset()
        let r = self.reconnecting
        self.reconnecting = false
        let p = self.param
        self.param = nil
        self.connectionListener?.onConnect(reconnecting: r, param: p)
    }

    func onDisconnected(connection: WebSocket, isServerOriginated clean: Bool, closeCode: URLSessionWebSocketTask.CloseCode, reason: String) {
        self.connectionListener?.onDisconnect(isServerOriginated: clean, code: closeCode, reason: reason)
        guard !self.reconnecting else {
            return
        }
        self.reconnecting = self.autoreconnect
        if self.autoreconnect {
            self.connectWithBackoffAsync()
        }
    }

    func onError(connection: WebSocket, error: Error) {
        self.connectionListener?.onError(error: error)
    }

    func onMessage(connection: WebSocket, text: String) {
        self.connectionListener?.onMessage(with: text)
    }

    func onMessage(connection: WebSocket, data: Data) {
        // Unexpected data message.
    }

    private func maybeInitReconnectClosure() {
        if reconnectClosure?.isCancelled ?? true {
            reconnectClosure = DispatchWorkItem {
                self.connectSocket()
                if self.isConnected {
                    self.reconnecting = false
                    return
                }
                self.connectWithBackoffAsync()
            }
        }
    }

    private func createUrlRequest() throws -> URLRequest {
        var request = URLRequest(url: endpointComponenets.url!)
        request.addValue(apiKey, forHTTPHeaderField: "X-Tinode-APIKey")
        return request
    }

    private func openConnection(with urlRequest: URLRequest) {
        self.webSocketConnection?.connect(req: urlRequest)
    }
    private func connectSocket() {
        guard !isConnected else { return }
        let request = try! createUrlRequest()
        self.openConnection(with: request)
    }

    private func connectWithBackoffAsync() {
        let delay = Double(self.backoffSteps.getNextDelay()) / 1000
        maybeInitReconnectClosure()
        self.connectQueue.asyncAfter(deadline: .now() + delay, execute: reconnectClosure!)
    }

    @discardableResult
    func connect(reconnectAutomatically: Bool = true, withParam param: Any?) throws -> Bool {
        self.autoreconnect = reconnectAutomatically
        self.param = param
        if self.autoreconnect && self.reconnecting {
            // If we are trying to reconnect, do it now
            // (we simply reset the exp backoff steps).
            reconnectClosure!.cancel()
            backoffSteps.reset()
            connectWithBackoffAsync()
        } else {
            connectSocket()
        }
        return true
    }

    func disconnect() {
        webSocketConnection?.close()
        if autoreconnect {
            autoreconnect = false
            reconnectClosure!.cancel()
        }
    }

    func send(payload data: Data) {
        webSocketConnection?.send(data: data)
    }

}

protocol ConnectionListener {
    func onConnect(reconnecting: Bool, param: Any?)
    func onMessage(with message: String)
    func onDisconnect(isServerOriginated: Bool, code: URLSessionWebSocketTask.CloseCode, reason: String)
    func onError(error: Error)
}
