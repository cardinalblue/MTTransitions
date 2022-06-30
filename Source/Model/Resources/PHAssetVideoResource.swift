//
//  PHAssetVideoResource.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/30.
//

import Photos
import Foundation

public class PHAssetVideoResource: Resource {

    public let phAsset: PHAsset

    private var avAsset: AVAsset?

    public let imageManager: PHImageManager

    // MARK: Resource properties

    public var size: CGSize

    public var duration: CMTime

    public var selectedTimeRange: CMTimeRange

    public var status: ResourceStatus = .unavailable(ResourceError.isEmpty)

    // MARK: Object lifecycle

    public init(phAsset: PHAsset, imageManager: PHImageManager = .default()) {
        self.phAsset = phAsset
        self.imageManager = imageManager
        self.size = CGSize(width: phAsset.pixelWidth, height: phAsset.pixelHeight)
        self.duration = CMTime(value: Int64(phAsset.duration * 600), timescale: 600)
        self.selectedTimeRange = CMTimeRangeMake(start: CMTime.zero, duration: duration)
    }

    // MARK: Resource functions

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
        guard let avAsset = avAsset else {
            return []
        }
        return avAsset.tracks(withMediaType: type)
    }

    public func trackInfo(for type: AVMediaType, at index: Int) -> ResourceTrackInfo {
        let track = tracks(for: type)[index]
        return ResourceTrackInfo(track: track, selectedTimeRange: selectedTimeRange, scaleToDuration: nil)
    }

    // MARK: - Load

    @discardableResult
    public func prepare(
        progressHandler:((Double) -> Void)? = nil,
        completion: @escaping (ResourceStatus) -> Void
    ) -> ResourceTask? {
        switch status {
        case .available:
            completion(.available)
            return nil
        case .unavailable:
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.progressHandler = { (progress, error, stop, info) in
                if let isCancelled = info?[PHImageCancelledKey] as? NSNumber, isCancelled.boolValue {
                    return
                }
                if error != nil {
                    return
                }
                DispatchQueue.main.async {
                    progressHandler?(progress)
                }
            }

            let requestID = imageManager.requestAVAsset(
                forVideo: phAsset, options: options
            ) { [weak self] (asset, audioMix, info) in
                guard let self = self else { return }

                if let asset = asset {
                    self.avAsset = asset
                    self.duration = asset.duration
                    if let track = asset.tracks(withMediaType: .video).first {
                        self.size = track.naturalSize.applying(track.preferredTransform)
                    }
                    self.status = .available
                } else {
                    let error: Error? = { () -> Error? in
                        if let requestError = info?[PHImageErrorKey] as? Error {
                            return requestError
                        }
                        return ResourceError.isEmpty
                    }()
                    self.status = .unavailable(error)
                }
                DispatchQueue.main.async {
                    completion(self.status)
                }
            }

            return ResourceTask(cancel: {
                PHImageManager.default().cancelImageRequest(requestID)
            })
        }
    }

}
