//
//  AsyncOp.swift
//  MTTransitionsDemo
//
//  Created by Jim Wang on 2022/12/12.
//  Copyright © 2022 xu.shuifeng. All rights reserved.
//

import Foundation

open class CBAsyncOperation<T>: Operation
{
    open var result: T?

    // MARK: State
    enum State {
        case ready
        case executing
        case finished

        // Keypath for KVO
        fileprivate func keyPath() -> String {
            switch self {
            case .ready:
                return "isReady"
            case .executing:
                return "isExecuting"
            case .finished:
                return "isFinished"
            }
        }
    }

    // MARK: - Properties

    var state: State = .ready {
        willSet {
            willChangeValue(forKey: state.keyPath())
            willChangeValue(forKey: newValue.keyPath())
        }
        didSet {
            didChangeValue(forKey: oldValue.keyPath())
            didChangeValue(forKey: state.keyPath())
        }
    }

    override open var isReady: Bool {
        return super.isReady && state == .ready
    }

    override open var isExecuting: Bool {
        return state == .executing
    }

    override open var isFinished: Bool {
        return state == .finished
    }

    override open var isAsynchronous: Bool {
        return true
    }

    // MARK: - Executing the operation

    override open func start() {
        if isCancelled {
            state = .finished
            return
        }

        main()
    }

    final override public func main() {
        if isCancelled {
            state = .finished
            return
        }
        state = .executing
        workItem()
    }

    open override func cancel() {
        super.cancel()
        if isExecuting {
            finish()
        }
    }

    final public func finish() {
        state = .finished
    }

    /// Override this method for your async task here.
    /// **Must** call `finish()` when aync task is finished.
    open func workItem() {
        finish()
    }

}
