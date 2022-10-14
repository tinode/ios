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

            self.connectedClients.append(newConnection)
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
        // Tinode will connect to localhost:6060 by default.
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
        func metaDescMsg(forId id: String?, onTopic topic: String?, currentTime now: Date,
                         defacs: Defacs?, acs: Acs?, lastSeen: Date?, pub: TheCard?, priv: PrivateType?) -> ServerMessage {
            let result = ServerMessage()
            let desc = Description<TheCard, PrivateType>()
            if topic == "me" {
                desc.created = now.addingTimeInterval(-86400)
                desc.updated = desc.created
                desc.touched = desc.created
            }
            desc.defacs = defacs
            desc.acs = acs
            desc.pub = pub
            desc.priv = priv
            if let lastSeen = lastSeen {
                desc.seen = LastSeen(when: lastSeen, ua: "dummy")
            }
            result.meta = MsgServerMeta(id: id, topic: topic, ts: now, desc: desc, sub: nil, del: nil, tags: nil, cred: nil)

            return result
        }
        func subMsg(topic: String, updatedTs: Date?, read: Int, recv: Int, acs: Acs?, pub: TheCard?, priv: PrivateType?) -> DefaultSubscription {
            let sub = DefaultSubscription()
            sub.topic = topic
            sub.updated = updatedTs
            sub.read = read
            sub.recv = recv
            sub.pub = pub
            sub.priv = priv
            sub.acs = acs
            return sub
        }
        tinodeServer.addHandler(forRequestType: .sub, handler: { req in
            let sreq = req.sub!
            guard let topic = sreq.topic else { return [] }
            switch topic {
            case "me":
                let now = Date()
                let responseCtrl = ServerMessage()
                responseCtrl.ctrl = MsgServerCtrl(id: sreq.id, topic: sreq.topic, code: 200, text: "ok", ts: now, params: nil)

                let metaDesc = metaDescMsg(forId: sreq.id, onTopic: "me", currentTime: now, defacs: Defacs(auth: "JRWPA", anon: "N"), acs: nil, lastSeen: nil, pub: TheCard(fn: "Alice"), priv: ["comment": .string("no comment")])

                let metaSub = ServerMessage()
                let subBob = subMsg(topic: "usrBob", updatedTs: now.addingTimeInterval(-86400), read: 2, recv: 2, acs: Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS"), pub: TheCard(fn: "Bob"), priv: ["comment": .string("bla")])

                let subGrp = subMsg(topic: "grpGroup", updatedTs: now.addingTimeInterval(-100000), read: 0, recv: 0, acs: Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS"), pub: TheCard(fn: "Test group"), priv: ["comment": .string("Group description")])
                metaSub.meta = MsgServerMeta(id: sreq.id, topic: "me", ts: now, desc: nil, sub: [subBob, subGrp], del: nil, tags: nil, cred: nil)
                return [responseCtrl, metaDesc, metaSub]
            case "usrBob":
                let now = Date()
                let responseCtrl = ServerMessage()
                responseCtrl.ctrl = MsgServerCtrl(id: sreq.id, topic: sreq.topic, code: 200, text: "ok", ts: now, params: nil)

                let metaDesc = metaDescMsg(forId: sreq.id, onTopic: sreq.topic, currentTime: now, defacs: nil, acs: Acs(given: "JRWPA", want: "JRWPA", mode: "JRWPA"), lastSeen: now.addingTimeInterval(-10), pub: nil, priv: nil)

                let metaSub = ServerMessage()
                let sub1 = subMsg(topic: "usrBob", updatedTs: now.addingTimeInterval(-100), read: 2, recv: 2, acs: Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS"), pub: nil, priv: nil)
                let sub2 = subMsg(topic: "usrAlice", updatedTs: now.addingTimeInterval(-100), read: 2, recv: 2, acs: Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS"), pub: nil, priv: nil)
                metaSub.meta = MsgServerMeta(id: sreq.id, topic: sreq.topic, ts: now, desc: nil, sub: [sub1, sub2], del: nil, tags: nil, cred: nil)

                let data1 = ServerMessage()
                data1.data = MsgServerData(id: sreq.id, topic: sreq.topic, from: sreq.topic, ts: now.addingTimeInterval(-2000), head: nil, seq: 1, content: Drafty(plainText: "hello message"))

                let data2 = ServerMessage()
                data2.data = MsgServerData(id: sreq.id, topic: sreq.topic, from: "usrAlice", ts: now.addingTimeInterval(-1000), head: nil, seq: 2, content: Drafty(plainText: "wassup?"))

                return [responseCtrl, metaDesc, metaSub, data1, data2]
            case "grpGroup":
                let now = Date()
                let responseCtrl = ServerMessage()
                responseCtrl.ctrl = MsgServerCtrl(id: sreq.id, topic: sreq.topic, code: 200, text: "ok", ts: now, params: nil)

                let metaDesc = metaDescMsg(forId: sreq.id, onTopic: sreq.topic, currentTime: now, defacs: Defacs(auth: "JRWPS", anon: "JR"), acs: Acs(given: "JRWPA", want: "JRWPA", mode: "JRWPA"), lastSeen: nil, pub: nil, priv: nil)

                let metaSub = ServerMessage()
                let sub1 = subMsg(topic: "usrBob", updatedTs: now.addingTimeInterval(-100000), read: 0, recv: 0, acs: Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS"), pub: nil, priv: nil)
                let sub2 = subMsg(topic: "usrAlice", updatedTs: now.addingTimeInterval(-100000), read: 0, recv: 0, acs: Acs(given: "JRWPASDO", want: "JRWPASDO", mode: "JRWPASDO"), pub: nil, priv: nil)
                metaSub.meta = MsgServerMeta(id: sreq.id, topic: sreq.topic, ts: now, desc: nil, sub: [sub1, sub2], del: nil, tags: nil, cred: nil)

                return [responseCtrl, metaDesc, metaSub]
            default:
                return []
            }
        })
    }

    private func pubHandler(responseSeq: Int) {
        tinodeServer.addHandler(forRequestType: .pub, handler: { req in
            let preq = req.pub!
            let now = Date()
            let responseCtrl = ServerMessage()
            responseCtrl.ctrl = MsgServerCtrl(id: preq.id, topic: preq.topic, code: 200, text: "accepted", ts: now,
                                              params: ["seq": .int(responseSeq)])
            return [responseCtrl]
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

        table.cells.waitForCount(2)
        XCTAssertTrue(table.staticTexts["Bob"].exists)
        XCTAssertTrue(table.staticTexts["Test group"].exists)
    }

    private func sendMessage(withContent content: String) {
        // Send another one.
        let inputField = app.children(matching: .window).element(boundBy: 1).children(matching: .other).element.children(matching: .other).element(boundBy: 1)
        inputField.tap()
        inputField.typeText(content)

        let arrowUpCircleButton = app.buttons["Arrow Up Circle"]
        arrowUpCircleButton.tap()
    }

    func testPublishP2P() {
        hiHandler()
        loginHandler(success: true)
        subHandler()
        pubHandler(responseSeq: 3)

        // Allow notifications.
        let monitor = allowLocalNotifications()
        defer { removeUIInterruptionMonitor(monitor) }

        logIntoTinode(shouldSucceed: true)

        // "Allow Notifications?" dialog. Make sure modal dialog handler gets triggered.
        app.tap()

        let table = app.tables.element
        XCTAssertTrue(table.exists)

        table.cells.waitForCount(2)
        let cell = table.cells.staticTexts["Bob"]
        cell.tap()
        let messageView = app.collectionViews.element

        // 2 messages.
        messageView.cells.waitForCount(2)
        XCTAssertTrue(messageView.containsMessage(text: "hello message"))
        XCTAssertTrue(messageView.containsMessage(text: "wassup?"))

        // Send another one.
        sendMessage(withContent: "new msg")

        // We should now have 3 messages.
        messageView.cells.waitForCount(3)
        XCTAssertTrue(messageView.containsMessage(text: "new msg"))
    }

    func testPublishGroup() {
        hiHandler()
        loginHandler(success: true)
        subHandler()
        pubHandler(responseSeq: 1)

        // Allow notifications.
        let monitor = allowLocalNotifications()
        defer { removeUIInterruptionMonitor(monitor) }

        logIntoTinode(shouldSucceed: true)

        // "Allow Notifications?" dialog. Make sure modal dialog handler gets triggered.
        app.tap()

        let table = app.tables.element
        XCTAssertTrue(table.exists)

        table.cells.waitForCount(2)
        let cell = table.cells.staticTexts["Test group"]
        cell.tap()
        let messageView = app.collectionViews.element

        // 0 messages.
        messageView.cells.waitForCount(0)

        // Send a message.
        sendMessage(withContent: "msg from alice")

        // We should now have 1 message.
        messageView.cells.waitForCount(1)
        XCTAssertTrue(messageView.containsMessage(text: "msg from alice"))

        // Simulate a message from Bob.
        let msgFromBob = ServerMessage()
        msgFromBob.data = MsgServerData(id: nil, topic: "grpGroup", from: "usrBob", ts: Date(), head: nil, seq: 2, content: Drafty(plainText: "msg from bob"))
        tinodeServer.sendResponse(response: msgFromBob, into: tinodeServer.connectedClients.first!)

        messageView.cells.waitForCount(2)
        XCTAssertTrue(messageView.containsMessage(text: "msg from bob"))
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

extension XCUIElementQuery {
    func waitForCount(_ count: Int) {
        let predicate = NSPredicate(format: "count == %d", count)
        let expectation = XCTNSPredicateExpectation(predicate: predicate,
                                                    object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: 2)
        XCTAssertEqual(result, XCTWaiter.Result.completed)
    }
}

extension XCUIElement {
    func containsMessage(text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        return self.descendants(matching: .textView).containing(predicate).element.exists
    }
}
