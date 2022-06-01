//
//  Clip.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/30.
//

import AVFoundation
import Foundation

public protocol VideoCompositionTrackProvider: AnyObject {
    func numberOfVideoTracks() -> Int
    func videoCompositionTrack(at index: Int, for composition: AVMutableComposition, preferredTrackID: Int32, timeRange: CMTimeRange) -> AVCompositionTrack?
}

public protocol AudioCompositionTrackProvider: AnyObject {
    func numberOfAudioTracks() -> Int
    func audioCompositionTrack(at index: Int, for composition: AVMutableComposition, preferredTrackID: Int32) -> AVCompositionTrack?
}

public class Clip {

    public var identifier: String
    public var resource: Resource

    //    public var videoConfiguration: VideoConfiguration = VideoConfiguration.createDefaultConfiguration()
    //    public var audioConfiguration: AudioConfiguration = .createDefaultConfiguration()
    //
    //    public var videoTransition: VideoTransition?
    //    public var audioTransition: AudioTransition?

    public var startTime: CMTime = CMTime.zero
    public var duration: CMTime {
        resource.selectedTimeRange.duration
    }

    public var timeRange: CMTimeRange {
        CMTimeRange(start: startTime, duration: duration)
    }

    public init(resource: Resource, identifier: String = UUID().uuidString) {
        self.identifier = identifier
        self.resource = resource
    }

    func prepare(completion: @escaping (ResourceStatus) -> Void) {
        _ = resource.prepare(progressHandler: nil, completion: completion)
    }
}

extension Clip: VideoCompositionTrackProvider {

    public func numberOfVideoTracks() -> Int {
        resource.tracks(for: .video).count
    }

    public func videoCompositionTrack(at index: Int, for composition: AVMutableComposition, preferredTrackID: Int32, timeRange: CMTimeRange) -> AVCompositionTrack? {
        let trackInfo = resource.trackInfo(for: .video, at: index)
        let track = trackInfo.track

        let compositionTrack: AVMutableCompositionTrack? = {
            if let track = composition.track(withTrackID: preferredTrackID) {
                return track
            }
            return composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: preferredTrackID)
        }()

        guard let compositionTrack = compositionTrack else {
            return nil
        }

        compositionTrack.preferredTransforms[timeRange.vf_identifier] = track.preferredTransform
        do {
//            compositionTrack.removeTimeRange(CMTimeRange(start: timeRange.start, duration: trackInfo.scaleToDuration))
            print("insert time range: \(trackInfo.selectedTimeRange) input: \(timeRange)")
            try compositionTrack.insertTimeRange(trackInfo.selectedTimeRange, of: trackInfo.track, at: timeRange.start)
//            compositionTrack.scaleTimeRange(CMTimeRange(start: timeRange.start, duration: trackInfo.selectedTimeRange.duration), toDuration: trackInfo.scaleToDuration)
        } catch {
            debugPrint(#function + error.localizedDescription)
        }
        return compositionTrack
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
