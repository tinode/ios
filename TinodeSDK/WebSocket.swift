//
//  WebSocket.swift
//  TinodeSDK
//
//  Created by Gene Sokolov on 03.01.2022.
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation

protocol WebSocketConnectionDelegate {
    func onConnected(connection: WebSocket)
    func onDisconnected(connection: WebSocket, isServerOriginated clean: Bool, closeCode: URLSessionWebSocketTask.CloseCode, reason: String)
    func onError(connection: WebSocket, error: Error)
    func onMessage(connection: WebSocket, text: String)
    func onMessage(connection: WebSocket, data: Data)
}

class WebSocket: NSObject, URLSessionWebSocketDelegate, URLSessionDelegate {
    private var delegate: WebSocketConnectionDelegate?
    private var socket: URLSessionWebSocketTask!
    private var urlSession: URLSession!
    private let webSocketQueue: DispatchQueue = DispatchQueue(label: "WebSocket.webSocketQueue")
    private lazy var delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "WebSocket.delegateQueue"
        queue.maxConcurrentOperationCount = 1
        queue.underlyingQueue = webSocketQueue
        return queue
    }()
    private var timeout: TimeInterval!
    private(set) var isConnected: Bool = false
    private(set) var isConnecting: Bool = false

    init(timeout: TimeInterval) {
        super.init()
        self.timeout = timeout
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
        isConnecting = false
        self.delegate?.onConnected(connection: self)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        isConnecting = false
        self.delegate?.onDisconnected(connection: self, isServerOriginated: true, closeCode: closeCode, reason: String(decoding: reason ?? Data(), as: UTF8.self))
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        /// Don't call delegate?.onDisconnected in this method. It would close the next connection.
        completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        isConnected = false
        isConnecting = false
        if let error = error as NSError? {
            if error.code == 57 /* timeout */ ||
                error.code == 60 /* no network */ ||
                error.code == 54 /* offline */ {
                close()
                delegate?.onDisconnected(connection: self, isServerOriginated: false, closeCode: .invalid, reason: error.localizedDescription)
            } else {
                delegate?.onError(connection: self, error: error)
            }
        }
    }

    func connect(req: URLRequest) {
        isConnecting = true
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
        socket = urlSession.webSocketTask(with: req)
        socket.resume()

        listen()
    }

    func close() {
        socket.cancel(with: .goingAway, reason: nil)
    }

    func send(text: String) {
        socket.send(URLSessionWebSocketTask.Message.string(text)) { error in
            if let error = error {
                self.delegate?.onError(connection: self, error: error)
            }
        }
    }

    func send(data: Data) {
        socket.send(URLSessionWebSocketTask.Message.data(data)) { error in
            if let error = error {
                self.delegate?.onError(connection: self, error: error)
            }
        }
    }

    private func listen()  {
        socket.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                self.delegate?.onError(connection: self, error: error)
            case .success(let message):
                switch message {
                case .string(let text):
                    self.delegate?.onMessage(connection: self, text: text)
                case .data(let data):
                    self.delegate?.onMessage(connection: self, data: data)
                @unknown default:
                    Tinode.log.error("Unknown WebSocket message type: %@", String(describing: message))
                }

                self.listen()
            }
        }
    }
}
