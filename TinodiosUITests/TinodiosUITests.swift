//
//  TinodiosUITests.swift
//  TinodiosUITests
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import XCTest

import Network
@testable import TinodeSDK

class FakeTinodeServer {
    var listener: NWListener
    var connectedClients: [NWConnection] = []

    // Request types.
    enum RequestType {
        case none, hi, acc, login, sub, get, set, pub, leave, note, del
    }
    // Request handlers.
    var requestHandlers: [RequestType : ((ClientMessage<Int, Int>) -> [ServerMessage])] = [:]

    init(port: UInt16) {
        let parameters = NWParameters(tls: nil)
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            if let port = NWEndpoint.Port(rawValue: port) {
                listener = try NWListener(using: parameters, on: port)
            } else {
                fatalError("Unable to start WebSocket server on port \(port)")
            }
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    func startServer() {
        let serverQueue = DispatchQueue(label: "ServerQueue")

        listener.newConnectionHandler = { newConnection in
            print("New connection connecting")

            func receive() {
                newConnection.receiveMessage { (data, context, isComplete, error) in
                    if let data = data, let context = context {
                        print("Received a new message from client")
                        try! self.handleClientMessage(data: data, context: context, stringVal: "", connection: newConnection)
                        receive()
                    }
                }
            }
            receive()

            newConnection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("Client ready")
                case .failed(let error):
                    print("Client connection failed \(error.localizedDescription)")
                case .waiting(let error):
                    print("Waiting for long time \(error.localizedDescription)")
                default:
                    break
                }
            }

            newConnection.start(queue: serverQueue)
        }

        listener.stateUpdateHandler = { state in
            print(state)
            switch state {
            case .ready:
                print("Server Ready")
            case .failed(let error):
                print("Server failed with \(error.localizedDescription)")
            default:
                break
            }
        }

        listener.start(queue: serverQueue)
    }

    func stopServer() {
        listener.cancel()
    }

    func handleClientMessage(data: Data, context: NWConnection.ContentContext, stringVal: String, connection: NWConnection) throws {
        let message = try Tinode.jsonDecoder.decode(ClientMessage<Int, Int>.self, from: data)

        print("--> received: \(String(decoding: data, as: UTF8.self))")
        var reqType: RequestType = .none
        if message.hi != nil {
            reqType = .hi
        } else if message.login != nil {
            reqType = .login
        } else if message.sub != nil {
            reqType = .sub
        } else if message.get != nil {
            reqType = .get
        } else if message.set != nil {
            reqType = .set
        } else if message.pub != nil {
            reqType = .pub
        } else if message.leave != nil {
            reqType = .leave
        } else if message.note != nil {
            reqType = .note
        } else if message.del != nil {
            reqType = .del
        }
        self.requestHandlers[reqType]?(message).forEach { self.sendResponse(response: $0, into: connection) }
    }

    func addHandler(forRequestType type: RequestType, handler: @escaping ((ClientMessage<Int, Int>) -> [ServerMessage])) {
        self.requestHandlers[type] = handler
    }

    func sendResponse(response: ServerMessage, into connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "textContext",
                                                  metadata: [metadata])
        do {
            let data = try Tinode.jsonEncoder.encode(response)
            print("sending --> \(String(decoding: data, as: UTF8.self))")
            connection.send(content: data, contentContext: context, isComplete: true,
                            completion: .contentProcessed({ error in
                                if let error = error {
                                    print(error.localizedDescription)
                                }
                            }))
        } catch {
            print("Error sending response: \(error)")
        }
    }
}

final class TinodiosUITests: XCTestCase {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    var tinodeServer: FakeTinodeServer!
    var app: XCUIApplication!

    // Delete installed Tinode app.
    private func deleteTinode() {
        app.terminate()
        let icon = springboard.icons["Tinode"]
        if icon.exists {
            let iconFrame = icon.frame
            let springboardFrame = springboard.frame
            icon.press(forDuration: 5)

            // Tap the little "-" button at approximately where it is. The "-" is not exposed directly
            springboard.coordinate(withNormalizedOffset: CGVector(dx: (iconFrame.minX + 3) / springboardFrame.maxX, dy: (iconFrame.minY + 3) / springboardFrame.maxY)).tap()

            springboard.alerts.buttons["Delete App"].tap()
            // Confirm the choice once again.
            springboard.alerts.buttons["Delete"].tap()
        }
    }

    override func setUpWithError() throws {
        app = XCUIApplication()
        app.launch()
        tinodeServer = FakeTinodeServer(port: 6060)
        tinodeServer.startServer()

        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        deleteTinode()
        tinodeServer.requestHandlers.removeAll()
        tinodeServer.stopServer()
    }

    // Tinode message handlers.
    private func hiHandler() {
        tinodeServer.addHandler(forRequestType: .hi, handler: { req in
            let hi = req.hi!
            let response = ServerMessage()
            response.ctrl = MsgServerCtrl(id: hi.id, topic: nil, code: 200, text: "", ts: Date(), params: nil)
            return [response]
        })
    }

    private func loginHandler(success: Bool) {
        tinodeServer.addHandler(forRequestType: .login, handler: { req in
            let login = req.login!
            let response = ServerMessage()
            response.ctrl = success ?
                MsgServerCtrl(id: login.id, topic: nil, code: 200, text: "ok", ts: Date(),
                                          params: ["authlvl": .string("auth"), "token": .string("fake"),
                                                   "user": .string("usrAlice")]) :
                MsgServerCtrl(id: login.id, topic: nil, code: 401, text: "authentication failed", ts: Date(), params: nil)
            return [response]
        })
    }

    private func subHandler() {
        tinodeServer.addHandler(forRequestType: .sub, handler: { req in
            let sreq = req.sub!
            if sreq.topic == "me" {
                if let get = sreq.get, get.what.split(separator: " ").sorted().elementsEqual(["cred", "desc", "sub", "tags"]) {
                    let now = Date()
                    let responseCtrl = ServerMessage()
                    responseCtrl.ctrl = MsgServerCtrl(id: sreq.id, topic: sreq.topic, code: 200, text: "ok", ts: now, params: nil)

                    let metaDesc = ServerMessage()
                    let desc = Description<TheCard, PrivateType>()
                    desc.created = now.addingTimeInterval(-86400)
                    desc.updated = desc.created
                    desc.touched = desc.created
                    desc.defacs = Defacs(auth: "JRWPA", anon: "N")
                    desc.pub = TheCard(fn: "Alice")
                    desc.priv = ["comment": .string("no comment")]
                    metaDesc.meta = MsgServerMeta(id: sreq.id, topic: "me", ts: now, desc: desc, sub: nil, del: nil, tags: nil, cred: nil)

                    let metaSub = ServerMessage()
                    let sub = DefaultSubscription()
                    sub.topic = "usrBob"
                    sub.updated = now.addingTimeInterval(-86400)
                    sub.read = 2
                    sub.recv = 2
                    sub.pub = TheCard(fn: "Bob")
                    sub.priv = ["comment": .string("bla")]
                    sub.acs = Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS")
                    metaSub.meta = MsgServerMeta(id: sreq.id, topic: "me", ts: now, desc: nil, sub: [sub], del: nil, tags: nil, cred: nil)
                    return [responseCtrl, metaDesc, metaSub]
                }
            } else if sreq.topic == "usrBob" {
                if let get = sreq.get, get.what.split(separator: " ").sorted().elementsEqual(["data", "del", "desc", "sub"]) {
                    let now = Date()
                    let responseCtrl = ServerMessage()
                    responseCtrl.ctrl = MsgServerCtrl(id: sreq.id, topic: sreq.topic, code: 200, text: "ok", ts: now, params: nil)

                    let metaDesc = ServerMessage()
                    let desc = Description<TheCard, PrivateType>()
                    desc.acs = Acs(given: "JRWPA", want: "JRWPA", mode: "JRWPA")
                    desc.seen = LastSeen(when: now.addingTimeInterval(-100), ua: "my UA")
                    metaDesc.meta = MsgServerMeta(id: sreq.id, topic: sreq.topic, ts: now, desc: desc, sub: nil, del: nil, tags: nil, cred: nil)

                    let metaSub = ServerMessage()
                    let sub1 = DefaultSubscription()
                    sub1.topic = "usrBob"
                    sub1.updated = now.addingTimeInterval(-100)
                    sub1.read = 2
                    sub1.recv = 2
                    sub1.acs = Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS")

                    let sub2 = DefaultSubscription()
                    sub2.topic = "usrAlice"
                    sub2.updated = now.addingTimeInterval(-100)
                    sub2.read = 2
                    sub2.recv = 2
                    sub2.acs = Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS")

                    metaSub.meta = MsgServerMeta(id: sreq.id, topic: sreq.topic, ts: now, desc: nil, sub: [sub1, sub2], del: nil, tags: nil, cred: nil)

                    let data1 = ServerMessage()
                    data1.data = MsgServerData(id: sreq.id, topic: sreq.topic, from: sreq.topic, ts: now.addingTimeInterval(-2000), head: nil, seq: 1, content: Drafty(plainText: "hello message"))

                    let data2 = ServerMessage()
                    data2.data = MsgServerData(id: sreq.id, topic: sreq.topic, from: "usrAlice", ts: now.addingTimeInterval(-1000), head: nil, seq: 2, content: Drafty(plainText: "wassup?"))

                    return [responseCtrl, metaDesc, metaSub, data1, data2]
                }
            }
            return []
        })
    }

    private func allowLocalNotifications() -> NSObjectProtocol {
        return addUIInterruptionMonitor(withDescription: "Local Notifications") { (alert) -> Bool in
            let notifPermission = "Would Like to Send You Notifications"
            if alert.label.contains(notifPermission) {
                alert.buttons["Allow"].tap()
                return true
            }
            return false
        }
    }

    private func logIntoTinode(shouldSucceed: Bool) {
        // Log in as "alice".
        let elementsQuery = app.scrollViews.otherElements
        let loginText = elementsQuery.textFields["usernameText"]
        XCTAssertTrue(loginText.exists)
        loginText.tap()
        loginText.typeText("alice")

        let passwordText = elementsQuery.secureTextFields["passwordText"]
        XCTAssertTrue(passwordText.exists)
        passwordText.tap()
        passwordText.typeText("alice123")

        let signInButton = elementsQuery.staticTexts["Sign In"]
        XCTAssertTrue(signInButton.exists)
        signInButton.tap()

        // Check if user name field is still available. If so login has failed.
        XCTAssertNotEqual(loginText.exists, shouldSucceed)
    }

    func testLoginFailure() throws {
        hiHandler()
        loginHandler(success: false)

        logIntoTinode(shouldSucceed: false)
    }

    func testLoginBasic() throws {
        hiHandler()
        loginHandler(success: true)
        subHandler()

        // Allow notifications.
        let monitor = allowLocalNotifications()
        defer { removeUIInterruptionMonitor(monitor) }

        logIntoTinode(shouldSucceed: true)

        // "Allow Notifications?" dialog. Make sure modal dialog handler gets triggered.
        app.tap()

        let table = app.tables.element
        XCTAssertTrue(table.exists)

        let cell = table.cells.element(boundBy: 0)
        // Wait for UI to update asynchronously.
        let exists = NSPredicate(format: "exists == 1")
        expectation(for: exists, evaluatedWith: cell)
        waitForExpectations(timeout: 5, handler: nil)

        XCTAssertTrue(cell.staticTexts["Bob"].waitForExistence(timeout: 5))
    }

    func testPublishBasic() {
        hiHandler()
        loginHandler(success: true)
        subHandler()
        tinodeServer.addHandler(forRequestType: .pub, handler: { req in
            let preq = req.pub!
            let now = Date()
            let responseCtrl = ServerMessage()
            responseCtrl.ctrl = MsgServerCtrl(id: preq.id, topic: preq.topic, code: 200, text: "accepted", ts: now,
                                              params: ["seq": .int(3)])
            return [responseCtrl]
        })

        // Allow notifications.
        let monitor = allowLocalNotifications()
        defer { removeUIInterruptionMonitor(monitor) }

        logIntoTinode(shouldSucceed: true)

        // "Allow Notifications?" dialog. Make sure modal dialog handler gets triggered.
        app.tap()

        let table = app.tables.element
        XCTAssertTrue(table.exists)

        let cell = table.cells.element(boundBy: 0)
        // Wait for UI to update asynchronously.
        let exists = NSPredicate(format: "exists == 1")
        expectation(for: exists, evaluatedWith: cell)
        waitForExpectations(timeout: 5, handler: nil)

        XCTAssertTrue(cell.staticTexts["Bob"].waitForExistence(timeout: 5))

        cell.tap()
        let collectionViewsQuery = app.collectionViews
        sleep(1)

        // 2 messages.
        XCTAssertEqual(collectionViewsQuery.cells.count, 2)

        // Send another one.
        let inputField = app.children(matching: .window).element(boundBy: 1).children(matching: .other).element.children(matching: .other).element(boundBy: 1)
        inputField.tap()
        inputField.typeText("new msg")

        let arrowUpCircleButton = app.buttons["Arrow Up Circle"]
        arrowUpCircleButton.tap()

        sleep(1)
        // We should now have 3 messages.
        XCTAssertEqual(collectionViewsQuery.cells.count, 3)
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
