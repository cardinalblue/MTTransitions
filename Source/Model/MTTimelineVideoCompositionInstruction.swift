//
//  MTTimelineVideoCompositionInstruction.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/6/2.
//

import CoreImage
import AVFoundation
import Foundation

open class MTTimelineVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {

    open var timeRange: CMTimeRange = CMTimeRange()
    open var enablePostProcessing: Bool = false
    open var containsTweening: Bool = false
    open var requiredSourceTrackIDs: [NSValue]?
    open var passthroughTrackID: CMPersistentTrackID = 0

    open var layerInstructions: [MTTimelineVideoCompositionLayerInstruction] = []
//    public var passingThroughVideoCompositionProvider: VideoCompositionProvider?

    var transitionEffect: MTTransition.Effect?

    private lazy var transitionRenderer: MTVideoTransitionRenderer? = {
        guard let transitionEffect = transitionEffect else {
            return nil
        }
        return MTVideoTransitionRenderer(effect: transitionEffect)
    }()

    public var backgroundColor: CIColor = CIColor(red: 0, green: 0, blue: 0)

    public init(thePassthroughTrackID: CMPersistentTrackID, forTimeRange theTimeRange: CMTimeRange) {
        super.init()

        passthroughTrackID = thePassthroughTrackID
        timeRange = theTimeRange

        requiredSourceTrackIDs = [NSValue]()
        containsTweening = false
        enablePostProcessing = false
    }

    public init(theSourceTrackIDs: [NSValue], forTimeRange theTimeRange: CMTimeRange) {
        super.init()

        requiredSourceTrackIDs = theSourceTrackIDs
        timeRange = theTimeRange

        passthroughTrackID = kCMPersistentTrackID_Invalid
        containsTweening = true
        enablePostProcessing = false
    }

    open func apply(request: AVAsynchronousVideoCompositionRequest, renderContext: AVVideoCompositionRenderContext?) -> CIImage? {
        let time = request.compositionTime
        let renderSize = request.renderContext.size

        switch layerInstructions.count {
        case 1: // Passthrough
            var image: CIImage?
            let layerInstruction = layerInstructions.first!
            if let sourceFrame = request.sourceFrame(byTrackID: layerInstruction.trackID) {
                image = layerInstruction.apply(sourceImage: generateImage(from: sourceFrame), at: time, renderSize: renderSize)
            }
            return image
        case 2:  // Transition
            let foregroundLayerInstruction = layerInstructions.first!
            let backgroundLayerInstruction = layerInstructions.last!

            guard let foregroundSourceFrame = request.sourceFrame(byTrackID: foregroundLayerInstruction.trackID),
                  let backgroundSourceFrame = request.sourceFrame(byTrackID: backgroundLayerInstruction.trackID) else {
                      return nil
                  }

            let foregroundImage = foregroundLayerInstruction
                .apply(sourceImage: generateImage(from: foregroundSourceFrame), at: time, renderSize: renderSize)

            let backgroundImage = backgroundLayerInstruction
                .apply(sourceImage: generateImage(from: backgroundSourceFrame), at: time, renderSize: renderSize)

            let tweenFactor = factorForTimeInRange(request.compositionTime, range: request.videoCompositionInstruction.timeRange)

            guard let destPixelBuffer = renderContext?.newPixelBuffer(),
                  let foregroundSourceBuffer = renderContext?.newPixelBuffer(),
                  let backgroundSourceBuffer = renderContext?.newPixelBuffer() else {
                      return nil
                  }

            MTTimelineVideoCompositor.ciContext.render(foregroundImage, to: foregroundSourceBuffer)
            MTTimelineVideoCompositor.ciContext.render(backgroundImage, to: backgroundSourceBuffer)

            transitionRenderer?.renderPixelBuffer(destPixelBuffer,
                                                  usingForegroundSourceBuffer: foregroundSourceBuffer,
                                                  andBackgroundSourceBuffer: backgroundSourceBuffer,
                                                  forTweenFactor: Float(tweenFactor))
            let finalImage = generateImage(from: destPixelBuffer)
            return finalImage
        default:
            return nil
        }
    }

    /* 0.0 -> 1.0 */
    private func factorForTimeInRange( _ time: CMTime, range: CMTimeRange) -> Float64 {
        let elapsed = CMTimeSubtract(time, range.start)
        return CMTimeGetSeconds(elapsed) / CMTimeGetSeconds(range.duration)
    }

    private func generateImage(from pixelBuffer: CVPixelBuffer) -> CIImage {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let attr = CVBufferGetAttachments(pixelBuffer, .shouldPropagate) as? [ String : Any ]
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

    open override var debugDescription: String {
        return "<VideoCompositionInstruction, timeRange: {start: \(timeRange.start.seconds), duration: \(timeRange.duration.seconds)}, requiredSourceTrackIDs: \(String(describing: requiredSourceTrackIDs))}>"
    }
}

open class MTTimelineVideoCompositionLayerInstruction: CustomDebugStringConvertible {

    public var trackID: Int32
    public var videoCompositionProvider: VideoCompositionProvider
    public var timeRange: CMTimeRange = CMTimeRange.zero
    public var preferredTransform: CGAffineTransform?

    public init(trackID: Int32, videoCompositionProvider: VideoCompositionProvider) {
        self.trackID = trackID
        self.videoCompositionProvider = videoCompositionProvider
    }

    open func apply(sourceImage: CIImage, at time: CMTime, renderSize: CGSize) -> CIImage {
        var sourceImage = sourceImage
        if let preferredTransform = preferredTransform {
            sourceImage = sourceImage.flipYCoordinate().transformed(by: preferredTransform).flipYCoordinate()
        }
        let finalImage = videoCompositionProvider.applyEffect(to: sourceImage, at: time, renderSize: renderSize)

        return finalImage
    }

    public var debugDescription: String {
        return "<MTTimelineVideoCompositionLayerInstruction, trackID: \(trackID), timeRange: {start: \(timeRange.start.seconds), duration: \(timeRange.duration.seconds)}>"
    }
}


private extension CIImage {
    func flipYCoordinate() -> CIImage {
        let flipYTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: extent.origin.y * 2 + extent.height)
        return transformed(by: flipYTransform)
    }
}

