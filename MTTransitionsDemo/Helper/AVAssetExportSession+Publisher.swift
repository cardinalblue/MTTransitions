//
//  AVAssetExportSession+Publisher.swift
//  PicCollage
//
//  Created by Jim Wang on 2022/10/23.
//

import Combine
import AVFoundation
import UIKit
import Foundation

extension Publishers {

    public struct AVAssetExportSessionProgressPublisher: Publisher {
        public typealias Output = Float
        public typealias Failure = Never

        private let session: AVAssetExportSession

        public init(session: AVAssetExportSession) {
            self.session = session
        }

        public func receive<S>(subscriber: S) where S: Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            let subscription = AVAssetExportSessionProgressSubscription(subscriber: subscriber, session: session)
            subscriber.receive(subscription: subscription)
        }
    }

}

private final class AVAssetExportSessionProgressSubscription<S: Subscriber>: Subscription where S.Input == Float {
    private var subscriber: S?
    let session: AVAssetExportSession

    private var timerSubscription: AnyCancellable? {
        willSet {
            timerSubscription?.cancel()
        }
    }

    init(subscriber: S, session: AVAssetExportSession) {
        self.subscriber = subscriber
        self.session = session

        timerSubscription = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateProgress()
            }
    }

    func request(_ demand: Subscribers.Demand) {
        // Do nothing
    }

    func cancel() {
        subscriber = nil
        timerSubscription = nil
    }

    private func updateProgress() {
        switch session.status {
        case .exporting:
            let progress = session.progress
             // print("session progress \(session.progress)")
            _ = subscriber?.receive(progress)
        case .waiting, .cancelled, .unknown:
            _ = subscriber?.receive(0)
        case .completed, .failed:
            _ = subscriber?.receive(1)
            _ = subscriber?.receive(completion: .finished)
        default:
            break
        }
    }

    private func finish() {
        timerSubscription = nil
        _ = subscriber?.receive(completion: .finished)
    }
}

extension AVAssetExportSession {

    public func progressPublisher() -> Publishers.AVAssetExportSessionProgressPublisher {
        Publishers.AVAssetExportSessionProgressPublisher(session: self)
    }

}
