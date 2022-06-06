//
//  MTTimelineVideoCompositor.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/6/2.
//

import AVFoundation
import Foundation

import AVFoundation
import CoreImage

open class MTTimelineVideoCompositor: NSObject, AVFoundation.AVVideoCompositing  {

    public static var ciContext: CIContext = CIContext()
    private let renderContextQueue: DispatchQueue = DispatchQueue(label: "me.shuifeng.mttransitions.rendercontextqueue")
    private let renderingQueue: DispatchQueue = DispatchQueue(label: "me.shuifeng.mttransitions.renderingqueue")
    private var renderContextDidChange = false
    private var shouldCancelAllRequests = false
    private var renderContext: AVVideoCompositionRenderContext?

    public var sourcePixelBufferAttributes: [String : Any]? =
        [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
         String(kCVPixelBufferOpenGLESCompatibilityKey): true,
         String(kCVPixelBufferMetalCompatibilityKey): true]

    public var requiredPixelBufferAttributesForRenderContext: [String : Any] =
        [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
         String(kCVPixelBufferOpenGLESCompatibilityKey): true,
         String(kCVPixelBufferMetalCompatibilityKey): true]

    open func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContextQueue.sync(execute: { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.renderContext = newRenderContext
            strongSelf.renderContextDidChange = true
        })
    }

    public enum PixelBufferRequestError: Error {
        case newRenderedPixelBufferForRequestFailure
    }

    open func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderingQueue.async(execute: { [weak self] in
            guard let strongSelf = self else { return }
            if strongSelf.shouldCancelAllRequests {
                request.finishCancelledRequest()
            } else {
                autoreleasepool {
                    if let resultPixels = strongSelf.newRenderedPixelBufferForRequest(request: request) {
                        request.finish(withComposedVideoFrame: resultPixels)
                    } else {
                        request.finish(with: PixelBufferRequestError.newRenderedPixelBufferForRequestFailure)
                    }
                }
            }
        })
    }

    open func cancelAllPendingVideoCompositionRequests() {
        shouldCancelAllRequests = true
        renderingQueue.async(flags: .barrier) { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.shouldCancelAllRequests = false
        }
    }

    open func newRenderedPixelBufferForRequest(request: AVAsynchronousVideoCompositionRequest) -> CVPixelBuffer? {
        guard let outputPixels = renderContext?.newPixelBuffer() else { return nil }
        guard let instruction = request.videoCompositionInstruction as? MTTimelineVideoCompositionInstruction else {
            return nil
        }
        var image = CIImage(cvPixelBuffer: outputPixels)

        // Background
        let backgroundImage = CIImage(color: instruction.backgroundColor).cropped(to: image.extent)
        image = backgroundImage

        if let destinationImage = instruction.apply(request: request, renderContext: renderContext) {
            image = destinationImage.composited(over: image)
        }

        MTTimelineVideoCompositor.ciContext.render(image, to: outputPixels)

        return outputPixels
    }

}


//class MTTimelineVideoCompositor: NSObject, AVVideoCompositing {
//
//    public static var ciContext: CIContext = CIContext()
//
//    /// Returns the pixel buffer attributes required by the video compositor for new buffers created for processing.
//    var requiredPixelBufferAttributesForRenderContext: [String : Any] =
//        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
//
//    /// The pixel buffer attributes of pixel buffers that will be vended by the adaptor’s CVPixelBufferPool.
//    var sourcePixelBufferAttributes: [String : Any]? =
//        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
//
//    /// Set if all pending requests have been cancelled.
//    var shouldCancelAllRequests = false
//
//    /// Dispatch Queue used to issue custom compositor rendering work requests.
//    private let renderingQueue = DispatchQueue(label: "me.shuifeng.mttransitions.renderingqueue")
//
//    /// Dispatch Queue used to synchronize notifications that the composition will switch to a different render context.
//    private let renderContextQueue = DispatchQueue(label: "me.shuifeng.mttransitions.rendercontextqueue")
//
//    /// The current render context within which the custom compositor will render new output pixels buffers.
//    private var renderContext: AVVideoCompositionRenderContext?
//
//    /// Maintain the state of render context changes.
//    private var internalRenderContextDidChange = false
//    /// Actual state of render context changes.
//    private var renderContextDidChange: Bool {
//        get {
//            return renderContextQueue.sync { internalRenderContextDidChange }
//        }
//        set (newRenderContextDidChange) {
//            renderContextQueue.sync { internalRenderContextDidChange = newRenderContextDidChange }
//        }
//    }
//
//    private lazy var renderer = MTVideoTransitionRenderer(effect: effect)
//
//    /// Effect apply to video transition
//    var effect: MTTransition.Effect { return .angular }
//
//    override init() {
//        super.init()
//    }
//
//    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
//        renderContextQueue.sync { renderContext = newRenderContext }
//        renderContextDidChange = true
//    }
//
//    enum PixelBufferRequestError: Error {
//        case newRenderedPixelBufferForRequestFailure
//    }
//
//    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
//        autoreleasepool {
//            renderingQueue.async {
//                // Check if all pending requests have been cancelled.
//                if self.shouldCancelAllRequests {
//                    asyncVideoCompositionRequest.finishCancelledRequest()
//                } else {
//                    guard let currentInstruction = asyncVideoCompositionRequest.videoCompositionInstruction as? MTVideoCompositionInstruction else {
//                        return
//                    }
//
//                    let foregroundSourceBuffer = asyncVideoCompositionRequest.sourceFrame(byTrackID: currentInstruction.foregroundTrackID)
//                    let backgroundSourceBuffer = asyncVideoCompositionRequest.sourceFrame(byTrackID: currentInstruction.backgroundTrackID)
//
//                    switch (foregroundSourceBuffer, backgroundSourceBuffer) {
//                    case (.some, .none):
//                        guard let resultPixels = self.newRenderedPixelBuffer(asyncVideoCompositionRequest) else {
//                            asyncVideoCompositionRequest.finish(with: PixelBufferRequestError.newRenderedPixelBufferForRequestFailure)
//                            return
//                        }
//                        // The resulting pixelBuffer from Metal renderer is passed along to the request.
//                        asyncVideoCompositionRequest.finish(withComposedVideoFrame: resultPixels)
//                    case (.some, .some):
//                        if self.renderer.effect != currentInstruction.effect {
//                            self.renderer = MTVideoTransitionRenderer(effect: currentInstruction.effect)
//                        }
//                        guard let resultPixels = self.newRenderedPixelBufferForTransition(asyncVideoCompositionRequest) else {
//                            asyncVideoCompositionRequest.finish(with: PixelBufferRequestError.newRenderedPixelBufferForRequestFailure)
//                            return
//                        }
//                        // The resulting pixelBuffer from Metal renderer is passed along to the request.
//                        asyncVideoCompositionRequest.finish(withComposedVideoFrame: resultPixels)
//                    default:
//                        // The resulting pixelBuffer from Metal renderer is passed along to the request.
//                        asyncVideoCompositionRequest.finish(with: PixelBufferRequestError.newRenderedPixelBufferForRequestFailure)
//                    }
//                }
//            }
//        }
//    }
//
//    func cancelAllPendingVideoCompositionRequests() {
//        /*
//         Pending requests will call finishCancelledRequest, those already rendering will call
//         finishWithComposedVideoFrame.
//         */
//        renderingQueue.sync { shouldCancelAllRequests = true }
//        renderingQueue.async {
//            // Start accepting requests again.
//            self.shouldCancelAllRequests = false
//        }
//    }
//
//    func factorForTimeInRange( _ time: CMTime, range: CMTimeRange) -> Float64 { /* 0.0 -> 1.0 */
//        let elapsed = CMTimeSubtract(time, range.start)
//        return CMTimeGetSeconds(elapsed) / CMTimeGetSeconds(range.duration)
//    }
//
//    func newRenderedPixelBuffer(_ request: AVAsynchronousVideoCompositionRequest) -> CVPixelBuffer? {
//        guard let instruction = request.videoCompositionInstruction as? MTVideoCompositionInstruction else {
//            return nil
//        }
//
//        guard let outputPixels = renderContext?.newPixelBuffer() else {
//            return nil
//        }
//
//        guard let image = instruction.apply(request: request) else {
//            return nil
//        }
//
//        MTVideoCompositor.ciContext.render(image, to: outputPixels)
//
//        return outputPixels
//    }
//
//    func newRenderedPixelBufferForTransition(_ request: AVAsynchronousVideoCompositionRequest) -> CVPixelBuffer? {
//
//        /*
//         tweenFactor indicates how far within that timeRange are we rendering this frame. This is normalized to vary
//         between 0.0 and 1.0. 0.0 indicates the time at first frame in that videoComposition timeRange. 1.0 indicates
//         the time at last frame in that videoComposition timeRange.
//         */
//        let tweenFactor = factorForTimeInRange(request.compositionTime, range: request.videoCompositionInstruction.timeRange)
//
//        guard let currentInstruction = request.videoCompositionInstruction as? MTVideoCompositionInstruction else {
//            return nil
//        }
//
//        // Source pixel buffers are used as inputs while rendering the transition.
//        guard let foregroundSourceBuffer = renderContext?.newPixelBuffer(),
//              let backgroundSourceBuffer = renderContext?.newPixelBuffer() else {
//                  return nil
//              }
//
//        guard let (foreground, background) = currentInstruction.makeTransitionFrame(request: request) else {
//            return nil
//        }
//
//        MTVideoCompositor.ciContext.render(foreground, to: foregroundSourceBuffer)
//        MTVideoCompositor.ciContext.render(background, to: backgroundSourceBuffer)
//
//        // Destination pixel buffer into which we render the output.
//        guard let dstPixels = renderContext?.newPixelBuffer() else { return nil }
//
//        if renderContextDidChange { renderContextDidChange = false }
//
//        // Render transition
//        renderer.renderPixelBuffer(dstPixels,
//                                   usingForegroundSourceBuffer:foregroundSourceBuffer,
//                                   andBackgroundSourceBuffer:backgroundSourceBuffer,
//                                   forTweenFactor:Float(tweenFactor))
//
//        return dstPixels
//    }
//}
