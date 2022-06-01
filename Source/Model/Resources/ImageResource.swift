//
//  ImageResource.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/30.
//

import AVFoundation
import CoreMedia
import Foundation

class ImageResource: Resource {

    public var image: CIImage

    // MARK: Resource properties

    public var size: CGSize {
        image.extent.size
    }

    public var duration: CMTime

    public var selectedTimeRange: CMTimeRange

    public var status: ResourceStatus = .available

    // MARK: Object lifecycle

    public init(image: CIImage, duration: CMTime) {
        self.image = image
        self.status = .available
        self.duration = duration
        self.selectedTimeRange = CMTimeRange(start: CMTime.zero, duration: duration)
    }

    public func image(at time: CMTime, renderSize: CGSize) -> CIImage? {
        image
    }

    public func trackInfo(for type: AVMediaType, at index: Int) -> ResourceTrackInfo {
        let track = tracks(for: type)[index]
        return ResourceTrackInfo(track: track, selectedTimeRange: selectedTimeRange)
    }

    public func prepare(progressHandler: ((Double) -> Void)?, completion: @escaping (ResourceStatus) -> Void) -> ResourceTask? {
        completion(.available)
        return nil
    }

}
