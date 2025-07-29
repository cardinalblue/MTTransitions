//
//  AVAssetResource.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/30.
//

import AVFoundation
import CoreImage
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
            Task {
                if #available(iOS 16, *) {
                    do {
                        _ = try await asset.load(.tracks)
                    } catch {
                        debugPrint("load asset tracks with error: \(error)")
                    }
                } else {
                    await asset.loadValues(forKeys: ["tracks"])
                }
                if let track = asset.tracks(withMediaType: .video).first {
                    self.size = track.naturalSize.applying(track.preferredTransform)
                }
                completion(.available)
            }
            return ResourceTask {
                asset.cancelLoading()
            }
        }
    }

    // MARK: - Resource functions

    public func update(selectedTimeRange: CMTimeRange) throws {
        guard selectedTimeRange.start < duration else {
            throw ResourceError.outOfRange
        }
        self.selectedTimeRange = selectedTimeRange
    }

    public func image(at time: CMTime, renderSize: CGSize) -> CIImage? {
        nil
    }

    public func tracks(for type: AVMediaType) -> [AVAssetTrack] {
        asset.tracks(withMediaType: type)
    }

    public func trackInfo(for type: AVMediaType, at index: Int) -> ResourceTrackInfo {
        let track = tracks(for: type)[index]

        let adjustedTimeRange: CMTimeRange = { () -> CMTimeRange in
            if selectedTimeRange.end > duration {
                return CMTimeRange(start: selectedTimeRange.start, end: duration - selectedTimeRange.start)
            } else {
                return selectedTimeRange
            }
        }()

        return ResourceTrackInfo(track: track, selectedTimeRange: adjustedTimeRange, scaleToDuration: nil)
    }
}

