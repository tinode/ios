//
//  PromisedReply.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

enum PromisedReplyError: Error {
    case illegalStateError(String)
}

// Inspired by https://github.com/uber/swift-concurrency/blob/master/Sources/Concurrency/CountDownLatch.swift
private class CountDownLatch {
    private let condition = NSCondition()
    private var conditionCount: Int

    public init(count: Int) {
        assert(count >= 0, "CountDownLatch must have an initial count that is not negative.")
        conditionCount = count
    }
    public func countDown() {
        guard conditionCount > 0 else {
            return
        }
        condition.lock()
        conditionCount -= 1
        condition.broadcast()
        condition.unlock()
    }
    public func await() {
        guard conditionCount > 0 else {
            return
        }
        condition.lock()
        defer {
            condition.unlock()
        }
        while conditionCount > 0 {
            // We may be woken up by a broadcast in countDown.
            condition.wait()
        }
    }
}

public class PromisedReply<Value> {
    public typealias SuccessHandler = ((Value?) throws -> PromisedReply<Value>?)?
    public typealias FailureHandler = ((Error) throws -> PromisedReply<Value>?)?
    public typealias FinallyHandler = (() throws -> Void)
    enum State {
        case waiting
        case resolved(Value?)
        case rejected(Error)

        var isDone: Bool {
            switch self {
            case .resolved, .rejected:
                return true
            default:
                return false
            }
        }
    }

    private var state: State = .waiting
    private var successHandler: SuccessHandler = nil
    private var failureHandler: FailureHandler = nil
    private var nextPromise: PromisedReply<Value>?
    private var countDownLatch: CountDownLatch?
    private var queue = DispatchQueue(label: "co.tinode.promise")
    private(set) var creationTimestamp: Date = Date()
    var isResolved: Bool {
        if case .resolved = state { return true }
        return false
    }
    var isRejected: Bool {
        if case .rejected = state { return true }
        return false
    }
    var isDone: Bool {
        return state.isDone
    }

    public init() {
        countDownLatch = CountDownLatch(count: 1)
    }
    public init(value: Value) {
        state = .resolved(value)
        countDownLatch = CountDownLatch(count: 0)
    }
    public init(error: Error) {
        state = .rejected(error)
        countDownLatch = CountDownLatch(count: 0)
    }

    func resolve(result: Value?) throws {
        defer {
            // down the semaphore
            countDownLatch?.countDown()
        }
        try queue.sync {
            // critical section
            guard case .waiting = state else {
                throw PromisedReplyError.illegalStateError("Resolve: Promise already completed.")
            }
            state = .resolved(result)
            try callOnSuccess(result: result)
        }
    }

    func reject(error: Error) throws {
        defer {
            // down the semaphore
            countDownLatch?.countDown()
        }
        try queue.sync {
            // critical section
            guard case .waiting = state else {
                // down the semaphore
                throw PromisedReplyError.illegalStateError("Reject: promise already completed")
            }
            state = .rejected(error)
            try callOnFailure(err: error)
        }
    }
    @discardableResult
    public func then(onSuccess successHandler: SuccessHandler, onFailure failureHandler: FailureHandler = nil) -> PromisedReply<Value> {
        return queue.sync {
            // start critical section
            guard nextPromise == nil else {
                fatalError("Multiple calls to then are not supported")
            }
            self.successHandler = successHandler
            self.failureHandler = failureHandler
            self.nextPromise = PromisedReply<Value>()
            do {
                switch state {
                case .resolved(let result):
                    try callOnSuccess(result: result)
                case .rejected(let error):
                    try callOnFailure(err: error)
                case .waiting: break
                }
            } catch {
                self.nextPromise = PromisedReply<Value>(error: error)
            }
            return self.nextPromise!
        }
    }
    @discardableResult
    public func thenApply(_ successHandler: SuccessHandler) -> PromisedReply<Value> {
        return then(onSuccess: successHandler, onFailure: nil)
    }
    @discardableResult
    public func thenCatch(_ failureHandler: FailureHandler) -> PromisedReply<Value> {
        return then(onSuccess: nil, onFailure: failureHandler)
    }

    public func thenFinally(_ finally: @escaping FinallyHandler) {
        then(
            onSuccess: {
                msg in try finally()
                return nil
            },
            onFailure: {
                err in try finally()
                return nil
        })
    }

    private func callOnSuccess(result: Value?) throws {
        var ret: PromisedReply<Value>? = nil
        do {
            if let sh = successHandler {
                ret = try sh(result)
            }
        } catch {
            // failure handler
            try handleFailure(e: error)
            return
        }
        try handleSuccess(ret: ret)
    }

    private func callOnFailure(err: Error) throws {
        if let fh = failureHandler {
            // Try to recover.
            do {
                try handleSuccess(ret: fh(err))
            } catch {
                try handleFailure(e: error)
            }
        } else {
            // Pass to the next handler.
            try handleFailure(e: err)
        }
    }

    private func handleSuccess(ret: PromisedReply<Value>?) throws {
        guard let np = nextPromise else {
            if let r = ret, case .rejected(let retError) = r.state {
                throw retError
            }
            return
        }
        guard let r = ret else {
            // 'ret' is nil when an attempt is made at recovering from a failure. If the current
            // promise is rejected we should resolve the next in chain with the 'nil' value.
            let value: Value?
            switch state {
            case .resolved(let v): value = v
            default: value = nil
            }
            try np.resolve(result: value)
            return
        }
        switch r.state {
        case .resolved(let value):
            try np.resolve(result: value)
        case .rejected(let error):
            try np.reject(error: error)
        case .waiting:
            r.insertNextPromise(next: np)
        }
    }

    private func handleFailure(e: Error) throws {
        if let np = nextPromise {
            try np.reject(error: e)
        } else {
            throw e
        }
    }

    private func insertNextPromise(next: PromisedReply<Value>) {
        // critical section
        if let np = nextPromise {
            next.insertNextPromise(next: np)
        }
        nextPromise = next
    }

    public func getResult() throws -> Value? {
        countDownLatch?.await()
        switch state {
        case .resolved(let value):
            return value
        case .rejected(let e):
            throw e
        case .waiting:
            throw PromisedReplyError.illegalStateError("Called getResult on unresolved promise")
        }
    }
    @discardableResult
    public func waitResult() throws -> Bool {
        countDownLatch?.await()
        return isResolved
    }
}
