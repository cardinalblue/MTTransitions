//
//  PHAssetImageResource.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/30.
//

import Photos
import Foundation

open class PHAssetImageResource: Resource {

    public let asset: PHAsset
    public let imageManger: PHImageManager

    private var image: CIImage?

    // MARK: Resource properties

    public let size: CGSize

    public var duration: CMTime

    public var selectedTimeRange: CMTimeRange

    public var status: ResourceStatus = .unavailable(ResourceError.isEmpty)

    // MARK: Object lifecycle

    public init(asset: PHAsset, duration: CMTime, dimension: Int = 720,  imageManager: PHImageManager = PHImageManager.default()) {
        self.asset = asset
        self.size = { () -> CGSize in
            let w = CGFloat(asset.pixelWidth)
            let h = CGFloat(asset.pixelHeight)
            let sw = CGFloat(dimension) / w
            let sh = CGFloat(dimension) / h
            let scale = min(sw, sh)
            if scale > 1 {
                // The asset's size is not big enough to request the dimension we need.
                // Return the original size
                return CGSize(width: w, height: h)
            }
            return CGSize(width: w * scale, height: h * scale)
        }()
        self.duration = duration
        self.selectedTimeRange = CMTimeRange(start: CMTime.zero, duration: duration)
        self.imageManger = imageManager
    }

    public func image(at time: CMTime, renderSize: CGSize) -> CIImage? {
        return image
    }

    public func trackInfo(for type: AVMediaType, at index: Int) -> ResourceTrackInfo {
        let track = tracks(for: type)[index]
        return ResourceTrackInfo(track: track, selectedTimeRange: selectedTimeRange)
    }

    @discardableResult
    public func prepare(
        progressHandler:((Double) -> Void)? = nil,
        completion: @escaping (ResourceStatus) -> Void
    ) -> ResourceTask? {
        status = .unavailable(ResourceError.isEmpty)

        let progressHandler: PHAssetImageProgressHandler = { progress, error, stop, info in
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

        let imageRequestOptions = PHImageRequestOptions()
        imageRequestOptions.version = .current
        imageRequestOptions.deliveryMode = .highQualityFormat
        imageRequestOptions.isNetworkAccessAllowed = true
        imageRequestOptions.progressHandler = progressHandler

        let requestID = imageManger.requestImage(
            for: asset,
               targetSize: size,
               contentMode: .aspectFit,
               options: imageRequestOptions
        ) { [weak self] image, info in

            guard let self = self else { return }

            DispatchQueue.main.async {
                if let image = image {
                    self.image = CIImage(image: image)
                    self.status = .available
                    completion(self.status)
                } else {
                    let error: Error? = { () -> Error? in
                        if let requestError = info?[PHImageErrorKey] as? Error {
                            return requestError
                        }
                        return ResourceError.isEmpty
                    }()
                    self.status = .unavailable(error)
                    completion(self.status)
                }
            }
        }

        return ResourceTask(cancel: { [weak imageManger] in
            imageManger?.cancelImageRequest(requestID)
        })
    }

}
