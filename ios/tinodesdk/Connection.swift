//
//  Connection.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import SwiftWebSocket

class Connection {
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
    
    init(open url: URL, with apiKey: String, notify listener: ConnectionListener?) {
        self.apiKey = apiKey
        // TODO: apply necessary URL modifications.
        self.endpoint = url
        self.connectionListener = listener
        if url.scheme == "wss" || url.scheme == "https" {
            self.useTLS = true
        }
        self.webSocketConnection = WebSocket()
        webSocketConnection!.event.open = {
            print("opened")
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
    
    func connect() throws {
        let request = try! createUrlRequest()
        openConnection(with: request)
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
