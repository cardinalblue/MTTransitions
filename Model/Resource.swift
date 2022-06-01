//
//  Resource.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/30.
//

import AVFoundation
import Foundation

public protocol Resource {

    var size: CGSize { get }
    var duration: CMTime { get }

    /// Selected time range, indicate how many resources will be inserted to AVCompositionTrack
    var selectedTimeRange: CMTimeRange { get }

    /// Resource's status, indicate whether the tracks are available. Default is available
    var status: ResourceStatus { get }

    func prepare(progressHandler:((Double) -> Void)?, completion: @escaping (ResourceStatus) -> Void) -> ResourceTask?

    func image(at time: CMTime, renderSize: CGSize) -> CIImage?

    // MARK: Tracks
    func tracks(for type: AVMediaType) -> [AVAssetTrack]
    func trackInfo(for type: AVMediaType, at index: Int) -> ResourceTrackInfo

}

public struct ResourceTrackInfo {
    public var track: AVAssetTrack
    public var selectedTimeRange: CMTimeRange
    //    public var scaleToDuration: CMTime
}

public enum ResourceError: Error {
    case isEmpty
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
        let bundle = Bundle(for: AVAsset.Dummy.self)

        // For SPM
        if let videoURL = bundle.url(forResource: "black_empty", withExtension: "mp4") {
            return AVAsset(url: videoURL)
        }

        // For CocoaPods
        if let bundleURL = bundle.resourceURL?.appendingPathComponent("MTTransitions.bundle") {
            let resourceBundle = Bundle.init(url: bundleURL)
            if let videoURL = resourceBundle?.url(forResource: "black_empty", withExtension: "mp4") {
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

// MARK:

public class BaseResource {

    /// Max duration of this resource
    open var duration: CMTime = CMTime.zero

    public init() {}

    open func image(at time: CMTime, renderSize: CGSize) -> CIImage? {
        return nil
    }

}


//
//
//public protocol ResourceTrackInfoProvider: AnyObject {
//    func trackInfo(for type: AVMediaType, at index: Int) -> ResourceTrackInfo
//    func image(at time: CMTime, renderSize: CGSize) -> CIImage?
//}
//
//open class Resource: NSObject, NSCopying, ResourceTrackInfoProvider {
//
//    required override public init() {
//    }
//
//    /// Max duration of this resource
//    open var duration: CMTime = CMTime.zero
//
//    /// Selected time range, indicate how many resources will be inserted to AVCompositionTrack
//    open var selectedTimeRange: CMTimeRange = CMTimeRange.zero
//
//    private var _scaledDuration: CMTime = CMTime.invalid
//    public var scaledDuration: CMTime {
//        get {
//            if !_scaledDuration.isValid {
//                return selectedTimeRange.duration
//            }
//            return _scaledDuration
//        }
//        set {
//            _scaledDuration = newValue
//        }
//    }
//
//    public func sourceTime(for timelineTime: CMTime) -> CMTime {
//        let seconds = selectedTimeRange.start.seconds + timelineTime.seconds * (selectedTimeRange.duration.seconds / scaledDuration.seconds)
//        return CMTime(seconds: seconds, preferredTimescale: 600)
//    }
//
//    /// Natural frame size of this resource
//    open var size: CGSize = .zero
//
//
//    /// Provide tracks for specific media type
//    ///
//    /// - Parameter type: specific media type, currently only support AVMediaTypeVideo and AVMediaTypeAudio
//    /// - Returns: tracks
//    open func tracks(for type: AVMediaType) -> [AVAssetTrack] {
//        if let tracks = Resource.emptyAsset?.tracks(withMediaType: type) {
//            return tracks
//        }
//        return []
//    }
//
//    // MARK: - Load content
//
//    public enum ResourceStatus: Int {
//        case unavaliable
//        case avaliable
//    }
//
//    /// Resource's status, indicate weather the tracks are avaiable. Default is avaliable
//    public var status: ResourceStatus = .unavaliable
//    public var statusError: Error?
//
//    /// Load content makes it available to get tracks. When use load resource from PHAsset or internet resource, it's your responsibility to determinate when and where to load the content.
//    ///
//    /// - Parameters:
//    ///   - progressHandler: loading progress
//    ///   - completion: load completion
//    @discardableResult
//    open func prepare(progressHandler:((Double) -> Void)? = nil, completion: @escaping (ResourceStatus, Error?) -> Void) -> ResourceTask? {
//        completion(status, statusError)
//        return nil
//    }
//
//    // MARK: - NSCopying
//    open func copy(with zone: NSZone? = nil) -> Any {
//        let resource = type(of: self).init()
//        resource.size = size
//        resource.duration = duration
//        resource.selectedTimeRange = selectedTimeRange
//        resource.scaledDuration = scaledDuration
//        return resource
//    }
//
//    // MARK: - ResourceTrackInfoProvider
//
//    public func trackInfo(for type: AVMediaType, at index: Int) -> ResourceTrackInfo {
//        let track = tracks(for: type)[index]
//        let emptyDuration = CMTime(value: 1, 30)
//        let emptyTimeRange = CMTimeRangeMake(start: CMTime.zero, duration: emptyDuration)
//        return ResourceTrackInfo(track: track,
//                                 selectedTimeRange: emptyTimeRange,
//                                 scaleToDuration: scaledDuration)
//    }
//
//    open func image(at time: CMTime, renderSize: CGSize) -> CIImage? {
//        return nil
//    }
////
//}
//
//public extension Resource {
//    func setSpeed(_ speed: Float) {
//        scaledDuration = selectedTimeRange.duration * (1 / speed)
//    }
//}
