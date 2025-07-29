//
//  Configuration.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/26.
//

import AVFoundation
import Foundation

// ------------------------------

struct MTExtensionWrapper<Base> {
    let base: Base
    init(_ base: Base) {
        self.base = base
    }
}

protocol MTExtensionCompatible {
    associatedtype BaseType
    var mt: BaseType { get }
}

extension MTExtensionCompatible {
    var mt: MTExtensionWrapper<Self> {
        MTExtensionWrapper(self)
    }
}

// ------------------------------

public struct VideoConfigurationEffectInfo {
    public var time = CMTime.zero
    public var renderSize = CGSize.zero
    public var timeRange = CMTimeRange.zero
}

public class VideoConfiguration {

    public enum ContentMode {
        case aspectFit
        case aspectFill
        case custom
    }

    public var contentMode: ContentMode = .aspectFit

}

private extension AVAsset {

    enum AssociateKeys {
        static var key: Void?
    }

}

extension MTExtensionWrapper where Base: AVAsset {

    var configuration: VideoConfiguration? {
        get {
            objc_getAssociatedObject(base, &AVAsset.AssociateKeys.key) as? VideoConfiguration
        }
        set {
            objc_setAssociatedObject(base, &AVAsset.AssociateKeys.key, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

}
