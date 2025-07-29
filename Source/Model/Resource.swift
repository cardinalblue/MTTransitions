//
//  Resource.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/30.
//

import AVFoundation
import CoreImage
import Foundation

public protocol Resource {

    var size: CGSize { get }

    /// The max duration of this resource
    var duration: CMTime { get }

    /// Selected time range, indicate how many resources will be inserted to AVCompositionTrack
    var selectedTimeRange: CMTimeRange { get }

    /// Resource's status, indicate whether the tracks are available. Default is available
    var status: ResourceStatus { get }

    // The completion block must be called in your implementation.
    func prepare(progressHandler:((Double) -> Void)?, completion: @escaping (ResourceStatus) -> Void) -> ResourceTask?

    func update(selectedTimeRange: CMTimeRange) throws

    func image(at time: CMTime, renderSize: CGSize) -> CIImage?

    // MARK: Tracks
    func tracks(for type: AVMediaType) -> [AVAssetTrack]
    func trackInfo(for type: AVMediaType, at index: Int) -> ResourceTrackInfo
}

public struct ResourceTrackInfo {
    public var track: AVAssetTrack
    public var selectedTimeRange: CMTimeRange
    public var scaleToDuration: CMTime?
}

public enum ResourceError: Error {
    case isEmpty
    case outOfRange
}

public enum ResourceStatus {
    case unavailable(Error?)
    case available
}

public class ResourceTask {
    public var cancelHandler: (() -> Void)?

    public init(cancel: (() -> Void)? = nil) {
        self.cancelHandler = cancel
    }

    public func cancel() {
        cancelHandler?()
    }
}

private extension AVAsset {
    private class Dummy {}

    static let empty: AVAsset? = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: AVAsset.Dummy.self)
        #endif

        if let bundleUrl = bundle.url(forResource: "Assets", withExtension: "bundle"),
           let resourceBundle = Bundle(url: bundleUrl) {
            if let videoURL = resourceBundle.url(forResource: "black_empty", withExtension: "mp4") {
                return AVAsset(url: videoURL)
            }
        }

        // Otherwise fallback to main bundle
        if let url = Bundle.main.url(forResource: "black_empty", withExtension: "mp4") {
            let asset = AVAsset(url: url)
            return asset
        }

        return nil
    }()
}

extension Resource {

    public func tracks(for type: AVMediaType) -> [AVAssetTrack] {
        if let tracks = AVAsset.empty?.tracks(withMediaType: type) {
            return tracks
        }
        return []
    }

}
