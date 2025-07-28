//
//  MTVideoCompositionInstruction.swift
//  MTTransitions
//
//  Created by alexiscn on 2020/3/23.
//

import Foundation
import AVFoundation

class MTVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {

    enum Background {
        case color(CIColor)
        case blurred
    }

    /// ID used to identify the foreground frame.
    var foregroundTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    
    /// ID used to identify the background frame.
    var backgroundTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    
    /// Effect applied to video transition
    var effect: MTTransition.Effect = .angular

    var background: Background = .blurred //.color(CIColor(red: 0, green: 0, blue: 0))

    var configuration: VideoConfiguration?

    var timeRange: CMTimeRange {
        get { return self.overrideTimeRange }
        set { self.overrideTimeRange = newValue }
    }
    
    var enablePostProcessing: Bool {
        get { return self.overrideEnablePostProcessing }
        set { self.overrideEnablePostProcessing = newValue }
    }
    
    var containsTweening: Bool {
        get { return self.overrideContainsTweening }
        set { self.overrideContainsTweening = newValue }
    }
    
    var requiredSourceTrackIDs: [NSValue]? {
        get { return self.overrideRequiredSourceTrackIDs }
        set { self.overrideRequiredSourceTrackIDs = newValue }
    }
    
    var passthroughTrackID: CMPersistentTrackID {
        get { return self.overridePassthroughTrackID }
        set { self.overridePassthroughTrackID = newValue }
    }
    
    /// The timeRange during which instructions will be effective.
    private var overrideTimeRange: CMTimeRange = CMTimeRange()
    
    /// Indicates whether post-processing should be skipped for the duration of the instruction.
    private var overrideEnablePostProcessing = false
    
    /// Indicates whether to avoid some duplicate processing when rendering a frame from the same source and destinatin at different times.
    private var overrideContainsTweening = false
    
    /// The track IDs required to compose frames for the instruction.
    private var overrideRequiredSourceTrackIDs: [NSValue]?
    
    /// Track ID of the source frame when passthrough is in effect.
    private var overridePassthroughTrackID: CMPersistentTrackID = 0
    
    init(thePassthroughTrackID: CMPersistentTrackID, forTimeRange theTimeRange: CMTimeRange) {
        super.init()
        passthroughTrackID = thePassthroughTrackID
        timeRange = theTimeRange

        requiredSourceTrackIDs = [NSValue]()
        containsTweening = false
        enablePostProcessing = false
    }

    init(sourceTrackID: CMPersistentTrackID, forTimeRange theTimeRange: CMTimeRange) {
        super.init()

        foregroundTrackID = sourceTrackID
        requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
        timeRange = theTimeRange

        passthroughTrackID = kCMPersistentTrackID_Invalid
        containsTweening = true
        enablePostProcessing = false
    }
    
    init(theSourceTrackIDs: [NSValue], forTimeRange theTimeRange: CMTimeRange) {
        super.init()

        requiredSourceTrackIDs = theSourceTrackIDs
        timeRange = theTimeRange

        passthroughTrackID = kCMPersistentTrackID_Invalid
        containsTweening = true
        enablePostProcessing = false
    }

    func apply(request: AVAsynchronousVideoCompositionRequest) -> CIImage? {
        let renderSize = request.renderContext.size

        guard let foregroundSourceBuffer = request.sourceFrame(byTrackID: foregroundTrackID) else {
            return nil
        }

        let finalImage = makeCIImage(pixelBuffer: foregroundSourceBuffer, renderSize: renderSize)
        return finalImage
    }

    func makeTransitionFrame(request: AVAsynchronousVideoCompositionRequest) -> (foreground: CIImage, background: CIImage)? {
        let renderSize = request.renderContext.size
        let foreground = request.sourceFrame(byTrackID: foregroundTrackID).map { makeCIImage(pixelBuffer: $0, renderSize: renderSize) }
        let background = request.sourceFrame(byTrackID: backgroundTrackID).map { makeCIImage(pixelBuffer: $0, renderSize: renderSize) }

        guard let foreground = foreground, let background = background else {
            return nil
        }
        return (foreground, background)
    }
    
    private func makeCIImage(pixelBuffer: CVPixelBuffer, renderSize: CGSize) -> CIImage {
        var image = generateImage(from: pixelBuffer)

        let frame = CGRect(origin: CGPoint.zero, size: renderSize)
        let contentMode = configuration?.contentMode ?? .aspectFit
        switch contentMode {
        case .aspectFit:
            let transform = CGAffineTransform.transform(by: image.extent, aspectFitInRect: frame)
            image = image.transformed(by: transform).cropped(to: frame)
        case .aspectFill:
            let transform = CGAffineTransform.transform(by: image.extent, aspectFillRect: frame)
            image = image.transformed(by: transform).cropped(to: frame)
        case .custom:
            var transform = CGAffineTransform(
                scaleX: frame.size.width / image.extent.size.width,
                y: frame.size.height / image.extent.size.height
            )
            let translateTransform = CGAffineTransform.init(translationX: frame.origin.x, y: frame.origin.y)
            transform = transform.concatenating(translateTransform)
            image = image.transformed(by: transform)
        }

        // Background
        let backgroundImage = { () -> CIImage in
            switch background {
            case .color(let color):
                return CIImage(color: color).cropped(to: frame)
            case .blurred:
                let source = { () -> CIImage in
                    var image = generateImage(from: pixelBuffer)
                    let transform = CGAffineTransform.transform(by: image.extent, aspectFillRect: frame)
                    image = image.transformed(by: transform).cropped(to: frame)
                    return image
                }()

                // https://stackoverflow.com/questions/12839729/correct-crop-of-cigaussianblur
                let clampFilter = CIFilter(name: "CIAffineClamp")!
                clampFilter.setDefaults()
                clampFilter.setValue(source, forKey: kCIInputImageKey)

                let blurFilter = CIFilter(name: "CIGaussianBlur")!
                blurFilter.setValue(clampFilter.outputImage, forKey: kCIInputImageKey)
                blurFilter.setValue(50.0, forKey: "inputRadius")

                let output = blurFilter.outputImage!.cropped(to: frame)
                return output
            }
        }()

        let result = image.composited(over: backgroundImage)
        return result
    }

    private func generateImage(from pixelBuffer: CVPixelBuffer) -> CIImage {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let attr = CVBufferGetAttachments(pixelBuffer, .shouldPropagate) as? [String : Any]
        if let attr = attr, !attr.isEmpty {
            if let aspectRatioDict = attr[kCVImageBufferPixelAspectRatioKey as String] as? [ String : Any ], !aspectRatioDict.isEmpty {
                let width = aspectRatioDict[kCVImageBufferPixelAspectRatioHorizontalSpacingKey as String] as? CGFloat
                let height = aspectRatioDict[kCVImageBufferPixelAspectRatioVerticalSpacingKey as String] as? CGFloat
                if let width = width, let height = height,  width != 0 && height != 0 {
                    image = image.transformed(by: CGAffineTransform.identity.scaledBy(x: width / height, y: 1))
                }
            }
        }
        return image
    }

}

public extension CGRect {
    func aspectFit(in rect: CGRect) -> CGRect {
        let size = self.size.aspectFit(in: rect.size)
        let x = rect.origin.x + (rect.size.width - size.width) / 2
        let y = rect.origin.y + (rect.size.height - size.height) / 2
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    func aspectFill(in rect: CGRect) -> CGRect {
        let size = self.size.aspectFill(in: rect.size)
        let x = rect.origin.x + (rect.size.width - size.width) / 2
        let y = rect.origin.y + (rect.size.height - size.height) / 2
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

public extension CGSize {
    func aspectFit(in size: CGSize) -> CGSize {
        var aspectFitSize = size
        let widthRatio = size.width / width
        let heightRatio = size.height / height
        if(heightRatio < widthRatio) {
            aspectFitSize.width = round(heightRatio * width)
        } else if(widthRatio < heightRatio) {
            aspectFitSize.height = round(widthRatio * height)
        }
        return aspectFitSize
    }

    func aspectFill(in size: CGSize) -> CGSize {
        var aspectFillSize = size
        let widthRatio = size.width / width
        let heightRatio = size.height / height
        if(heightRatio > widthRatio) {
            aspectFillSize.width = heightRatio * width
        } else if(widthRatio > heightRatio) {
            aspectFillSize.height = widthRatio * height
        }
        return aspectFillSize
    }
}

public extension CGAffineTransform {
    static func transform(by sourceRect: CGRect, aspectFitInRect fitTargetRect: CGRect) -> CGAffineTransform {
        let fitRect = sourceRect.aspectFit(in: fitTargetRect)
        let xRatio = fitRect.size.width / sourceRect.size.width
        let yRatio = fitRect.size.height / sourceRect.size.height
        return CGAffineTransform(translationX: fitRect.origin.x - sourceRect.origin.x * xRatio, y: fitRect.origin.y - sourceRect.origin.y * yRatio).scaledBy(x: xRatio, y: yRatio)
    }

    static func transform(by size: CGSize, aspectFitInSize fitSize: CGSize) -> CGAffineTransform {
        let sourceRect = CGRect(origin: .zero, size: size)
        let fitTargetRect = CGRect(origin: .zero, size: fitSize)
        return transform(by: sourceRect, aspectFitInRect: fitTargetRect)
    }

    static func transform(by sourceRect: CGRect, aspectFillRect fillTargetRect: CGRect) -> CGAffineTransform {
        let fillRect = sourceRect.aspectFill(in: fillTargetRect)
        let xRatio = fillRect.size.width / sourceRect.size.width
        let yRatio = fillRect.size.height / sourceRect.size.height
        return CGAffineTransform(translationX: fillRect.origin.x - sourceRect.origin.x * xRatio, y: fillRect.origin.y - sourceRect.origin.y * yRatio).scaledBy(x: xRatio, y: yRatio)
    }

    static func transform(by size: CGSize, aspectFillSize fillSize: CGSize) -> CGAffineTransform {
        let sourceRect = CGRect(origin: .zero, size: size)
        let fillTargetRect = CGRect(origin: .zero, size: fillSize)
        return transform(by: sourceRect, aspectFillRect: fillTargetRect)
    }
}

public extension CGAffineTransform {
    func rotationRadians() -> CGFloat {
        return atan2(b, a)
    }

    func translation() -> CGPoint {
        return CGPoint(x: tx, y: ty)
    }

    func scaleXY() -> CGPoint {
        let scalex = sqrt(a * a + c * c)
        let scaley = sqrt(d * d + b * b)
        return CGPoint(x: scalex, y: scaley)
    }
}
