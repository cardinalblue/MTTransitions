//
//  VideoPostProcessing.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/6/2.
//

import CoreMedia
import Foundation

public struct VideoPostProcessingInfo {
    public var time = CMTime.zero
    public var renderSize = CGSize.zero
    public var timeRange = CMTimeRange.zero
}

public protocol VideoProcessing {
    func applyEffect(to sourceImage: CIImage, info: VideoPostProcessingInfo) -> CIImage
}

// MARK: Basic

public class BasicVideoConfiguration: VideoProcessing {

    public static func createDefaultConfiguration() -> BasicVideoConfiguration {
        return BasicVideoConfiguration()
    }

    public enum BaseContentMode {
        case aspectFit
        case aspectFill
        case custom
    }

    public enum Background {
        case color(CIColor)
        case blurred
    }

    public var contentMode: BaseContentMode = .aspectFit
    /// Default is renderSize
    public var frame: CGRect?
    public var transform: CGAffineTransform?
    public var opacity: Float = 1.0
    public var configurations: [VideoProcessing] = []
    public var background: Background? = .blurred

//    // MARK: - NSCopying

//    public func copy(with zone: NSZone? = nil) -> Any {
//        let configuration = type(of: self).init()
//        configuration.contentMode = contentMode
//        configuration.transform = transform
//        configuration.opacity = opacity;
//        configuration.configurations = configurations.map({ $0.copy(with: zone) as! VideoConfigurationProtocol });
//        configuration.frame = frame;
//        return configuration
//    }

    // MARK: - VideoConfigurationProtocol

    public func applyEffect(to sourceImage: CIImage, info: VideoPostProcessingInfo) -> CIImage {
        var finalImage = sourceImage

        if let userTransform = self.transform {
            var transform = CGAffineTransform.identity
            transform = transform.concatenating(CGAffineTransform(translationX: -(finalImage.extent.origin.x + finalImage.extent.width/2), y: -(finalImage.extent.origin.y + finalImage.extent.height/2)))
            transform = transform.concatenating(userTransform)
            transform = transform.concatenating(CGAffineTransform(translationX: (finalImage.extent.origin.x + finalImage.extent.width/2), y: (finalImage.extent.origin.y + finalImage.extent.height/2)))
            finalImage = finalImage.transformed(by: transform)
        }

        let frame = self.frame ?? CGRect(origin: CGPoint.zero, size: info.renderSize)
        switch contentMode {
        case .aspectFit:
            let transform = CGAffineTransform.transform(by: finalImage.extent, aspectFitInRect: frame)
            finalImage = finalImage.transformed(by: transform).cropped(to: frame)
            break
        case .aspectFill:
            let transform = CGAffineTransform.transform(by: finalImage.extent, aspectFillRect: frame)
            finalImage = finalImage.transformed(by: transform).cropped(to: frame)
            break
        case .custom:
            var transform = CGAffineTransform(scaleX: frame.size.width / sourceImage.extent.size.width, y: frame.size.height / sourceImage.extent.size.height)
            let translateTransform = CGAffineTransform.init(translationX: frame.origin.x, y: frame.origin.y)
            transform = transform.concatenating(translateTransform)
            finalImage = finalImage.transformed(by: transform)
            break
        }

        finalImage = finalImage.apply(alpha: CGFloat(opacity))

        configurations.forEach { (videoConfiguration) in
            finalImage = videoConfiguration.applyEffect(to: finalImage, info: info)
        }

        // Background
        let backgroundImage = { () -> CIImage? in
            if contentMode == .aspectFill {
                return nil
            }

            let bounds = CGRect(origin: .zero, size: info.renderSize)

            switch background {
            case .none:
                return nil
            case .color(let color):
                return CIImage(color: color).cropped(to: bounds)
            case .blurred:
                let source = { () -> CIImage in
                    let transform = CGAffineTransform.transform(by: sourceImage.extent, aspectFillRect: bounds)
                    return sourceImage.transformed(by: transform).cropped(to: bounds)
                }()

                // https://stackoverflow.com/questions/12839729/correct-crop-of-cigaussianblur
                let clampFilter = CIFilter(name: "CIAffineClamp")!
                clampFilter.setDefaults()
                clampFilter.setValue(source, forKey: kCIInputImageKey)

                let blurFilter = CIFilter(name: "CIGaussianBlur")!
                blurFilter.setValue(clampFilter.outputImage, forKey: kCIInputImageKey)
                blurFilter.setValue(50.0, forKey: "inputRadius")

                let output = blurFilter.outputImage!.cropped(to: bounds)
                return output
            }

        }()

        if let backgroundImage = backgroundImage {
            finalImage = finalImage.composited(over: backgroundImage)
        }

        return finalImage
    }
}
