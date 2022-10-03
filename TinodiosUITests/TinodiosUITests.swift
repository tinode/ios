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
    var tinodeServer: FakeTinodeServer!

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
        tinodeServer = FakeTinodeServer(port: 6060)
        tinodeServer.startServer()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
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
                                                   "user": .string("usrFake")]) :
                MsgServerCtrl(id: login.id, topic: nil, code: 401, text: "authentication failed", ts: Date(), params: nil)
            return [response]
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

    func testLoginFailure() throws {
        hiHandler()
        loginHandler(success: false)

        let app = XCUIApplication()
        app.launch()

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

        // Check if user name field is still available, i.e. login has failed.
        XCTAssertTrue(loginText.exists)
    }

    func testLoginBasic() throws {
        hiHandler()
        loginHandler(success: true)
        tinodeServer.addHandler(forRequestType: .sub, handler: { req in
            let sreq = req.sub!
            if sreq.topic == "me", let get = sreq.get, get.what.split(separator: " ").sorted().elementsEqual(["cred", "desc", "sub", "tags"]) {
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
            return []
        })

        // Allow notifications.
        let monitor = allowLocalNotifications()
        defer { removeUIInterruptionMonitor(monitor) }

        let app = XCUIApplication()
        app.launch()

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

        // Check if user name field is not still available, i.e. login succeeded.
        XCTAssertFalse(loginText.exists)

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

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
