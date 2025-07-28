//
//  Clip.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/30.
//

import AVFoundation
import CoreImage
import Foundation

public protocol VideoCompositionProvider: AnyObject {

    /// Apply effect to sourceImage
    ///
    /// - Parameters:
    ///   - sourceImage: sourceImage is the original image from resource
    ///   - time: time in timeline
    ///   - renderSize: the video canvas size
    /// - Returns: result image after apply effect
    func applyEffect(to sourceImage: CIImage, at time: CMTime, renderSize: CGSize) -> CIImage
}

public class Clip {

    public var identifier: String
    public var resource: Resource

    public var isVideoTrackEnabled: Bool = true
    public var isAudioTrackEnabled: Bool = true

    public var preferredTransform: CGAffineTransform? {
        resource.tracks(for: .video).first?.preferredTransform
    }

    public var videoPostProcessing: VideoProcessing? = BasicVideoConfiguration.createDefaultConfiguration()

    //    public var audioConfiguration: AudioConfiguration = .createDefaultConfiguration()    //

    public var startTime: CMTime = CMTime.zero
    public var duration: CMTime {
        resource.selectedTimeRange.duration
    }

    public var timeRange: CMTimeRange {
        CMTimeRange(start: startTime, duration: duration)
    }

    public var isReady: Bool {
        switch resource.status {
        case .available:
            return true
        default:
            return false
        }
    }

    public init(resource: Resource, identifier: String = UUID().uuidString) {
        self.identifier = identifier
        self.resource = resource
    }

    public func prepare(completion: @escaping (ResourceStatus) -> Void) {
        _ = resource.prepare(progressHandler: nil, completion: completion)
    }

    public func numberOfAudioTracks() -> Int {
        guard isAudioTrackEnabled else {
            return 0
        }
        return resource.tracks(for: .audio).count
    }

    public func numberOfVideoTracks() -> Int {
        guard isVideoTrackEnabled else {
            return 0
        }
        return resource.tracks(for: .video).count
    }
}

extension Clip: VideoCompositionProvider {

    @available(iOS 13.0.0, *)
    public func prepare() async -> ResourceStatus {
        await withCheckedContinuation { continuation in
            prepare { status in
                continuation.resume(returning: status)
            }
        }
    }

    public func applyEffect(to sourceImage: CIImage, at time: CMTime, renderSize: CGSize) -> CIImage {
        var finalImage: CIImage = {
            let relativeTime = time - self.startTime
            if let sourceImage = resource.image(at: relativeTime, renderSize: renderSize) {
                return sourceImage
            }
            return sourceImage
        }()

        if let preferredTransform = preferredTransform, preferredTransform != .identity {
            finalImage = finalImage.flipYCoordinate().transformed(by: preferredTransform).flipYCoordinate()
        }

        if let videoPostProcessing = videoPostProcessing {
            let info = VideoPostProcessingInfo(time: time, renderSize: renderSize, timeRange: timeRange)
            finalImage = videoPostProcessing.applyEffect(to: finalImage, info: info)
        }
        return finalImage
    }

}

// MARK: Helper

extension AVCompositionTrack {

    private enum AssociateKeys {
        static var preferredTransformsKey: Void?
    }

    var preferredTransforms: [String: CGAffineTransform] {
        get {
            if let transforms = objc_getAssociatedObject(self, &AssociateKeys.preferredTransformsKey) as? [String: CGAffineTransform] {
                return transforms
            }
            let transforms: [String: CGAffineTransform] = [:]
            return transforms
        }
        set(newValue) {
            objc_setAssociatedObject(self, &AssociateKeys.preferredTransformsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

}

extension CMTimeRange {
    var vf_identifier: String {
        return "{\(String(format: "%.3f", start.seconds)), \(String(format: "%.3f", duration.seconds))}"
    }
}


extension AVMutableComposition {

    func addResource(trackID: Int32, with resourceTrackInfo: ResourceTrackInfo, at time: CMTime) throws {
        let assetTrack = resourceTrackInfo.track

        let compositionTrack: AVMutableCompositionTrack? = {
            if let track = track(withTrackID: trackID) {
                return track
            }
            return addMutableTrack(withMediaType: assetTrack.mediaType, preferredTrackID: trackID)
        }()

        guard let compositionTrack = compositionTrack else {
            throw MTTimelineCompositionError.noCompositionTrack
        }


        let selectedTimeRange = { () -> CMTimeRange in
            let duration = min(assetTrack.timeRange.duration, resourceTrackInfo.selectedTimeRange.duration)
            return CMTimeRange(start: resourceTrackInfo.selectedTimeRange.start, duration: duration)
        }()

        try compositionTrack.insertTimeRange(selectedTimeRange, of: resourceTrackInfo.track, at: time)

        //            if selectedTimeRange.duration < timeRange.duration {
        //                let emptyTimeRange = { () -> CMTimeRange in
        //                    let start = CMTimeAdd(timeRange.start, selectedTimeRange.duration)
        //                    let duration = CMTimeSubtract(timeRange.duration, selectedTimeRange.duration)
        //                    return CMTimeRange(start: start, duration: duration)
        //                }()
        //                compositionTrack.insertEmptyTimeRange(emptyTimeRange)
        //            }

        if let scaleToDuration = resourceTrackInfo.scaleToDuration {
            let timeRange = CMTimeRange(start: time, duration: selectedTimeRange.duration)
            compositionTrack.scaleTimeRange(timeRange, toDuration: scaleToDuration)
        }
    }

    func addResource(trackID: Int32, with resourceTrackInfo: ResourceTrackInfo, at time: CMTime, duration: CMTime) throws {
        let assetTrack = resourceTrackInfo.track

        let compositionTrack: AVMutableCompositionTrack? = {
            if let track = track(withTrackID: trackID) {
                return track
            }
            return addMutableTrack(withMediaType: assetTrack.mediaType, preferredTrackID: trackID)
        }()

        guard let compositionTrack = compositionTrack else {
            throw MTTimelineCompositionError.noCompositionTrack
        }

        let selectedTimeRange = CMTimeRange(start: time, duration: duration)
        try compositionTrack.insertTimeRange(selectedTimeRange, of: resourceTrackInfo.track, at: time)
    }

    func addResource(trackID: Int32, with resourceTrackInfo: ResourceTrackInfo, at: CMTime, timeRange: CMTimeRange, until: CMTime) throws {
        let assetTrack = resourceTrackInfo.track

        let compositionTrack: AVMutableCompositionTrack? = {
            if let track = track(withTrackID: trackID) {
                return track
            }
            return addMutableTrack(withMediaType: assetTrack.mediaType, preferredTrackID: trackID)
        }()

        guard let compositionTrack = compositionTrack else {
            throw MTTimelineCompositionError.noCompositionTrack
        }

        let times = CMTime.makeLoopTime(timeRange: timeRange, at: at, until: until)
        for time in times {
            try compositionTrack.insertTimeRange(time.timeRange, of: resourceTrackInfo.track, at: time.at)
        }
    }
}
