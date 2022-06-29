//
//  AVAssetResource.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/30.
//

import AVFoundation
import Foundation

public class AVAssetResource: Resource {

    public let asset: AVAsset

    // MARK: Resource properties

    public var size: CGSize

    public var duration: CMTime

    public var selectedTimeRange: CMTimeRange

    public var status: ResourceStatus = .available

    // MARK: Object lifecycle

    public init(asset: AVAsset, selectedTimeRange: CMTimeRange? = nil) {
        self.asset = asset
        self.duration = asset.duration
        self.selectedTimeRange = selectedTimeRange ?? CMTimeRange(start: CMTime.zero, duration: duration)

        // Calling `prepare` to load actual size information
        self.size = .zero
    }

    // MARK: - Load Media before use resource

    @discardableResult
    public func prepare(progressHandler:((Double) -> Void)? = nil, completion: @escaping (ResourceStatus) -> Void) -> ResourceTask? {
        switch status {
        case .available:
            completion(.available)
            return nil
        case .unavailable:
            let asset = self.asset
            asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"], completionHandler: { [weak self] in
                guard let self = self else { return }

                func finished() {
                    if asset.tracks.count > 0 {
                        if let track = asset.tracks(withMediaType: .video).first {
                            self.size = track.naturalSize.applying(track.preferredTransform)
                        }
                        self.status = .available
                        self.duration = asset.duration
                    }
                    DispatchQueue.main.async {
                        completion(self.status)
                    }
                }

                var error: NSError?
                let tracksStatus = asset.statusOfValue(forKey: "tracks", error: &error)
                if tracksStatus != .loaded {
                    self.status = .unavailable(error)
                    debugPrint("Failed to load tracks, status: \(tracksStatus), error: \(String(describing: error))")
                    finished()
                    return
                }

                let durationStatus = asset.statusOfValue(forKey: "duration", error: &error)
                if durationStatus != .loaded {
                    self.status = .unavailable(error);
                    debugPrint("Failed to duration tracks, status: \(tracksStatus), error: \(String(describing: error))")
                    finished()
                    return
                }
                finished()
            })

            return ResourceTask(cancel: {
                asset.cancelLoading()
            })
        }
    }

    // MARK: - Resource functions

    public func update(selectedTimeRange: CMTimeRange) throws {
        guard selectedTimeRange.start < duration else {
            throw ResourceError.outOfRange
        }
        if selectedTimeRange.end > duration {
            self.selectedTimeRange = CMTimeRange(start: selectedTimeRange.start, end: duration - selectedTimeRange.start)
        } else {
            self.selectedTimeRange = selectedTimeRange
        }
    }

    public func image(at time: CMTime, renderSize: CGSize) -> CIImage? {
        nil
    }

    public func tracks(for type: AVMediaType) -> [AVAssetTrack] {
        asset.tracks(withMediaType: type)
    }

    public func trackInfo(for type: AVMediaType, at index: Int) -> ResourceTrackInfo {
        let track = tracks(for: type)[index]
        return ResourceTrackInfo(track: track, selectedTimeRange: selectedTimeRange, scaleToDuration: nil)
    }

}

