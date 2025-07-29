//
//  MTVideoCompositor.swift
//  MTTransitions
//
//  Created by alexiscn on 2020/3/23.
//

import CoreImage
import AVFoundation

class MTVideoCompositor: NSObject, AVVideoCompositing {

    public static var ciContext: CIContext = CIContext()

    /// Returns the pixel buffer attributes required by the video compositor for new buffers created for processing.
    var requiredPixelBufferAttributesForRenderContext: [String : any Sendable] =
    [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    
    /// The pixel buffer attributes of pixel buffers that will be vended by the adaptor’s CVPixelBufferPool.
    var sourcePixelBufferAttributes: [String : any Sendable]? =
    [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    
    /// Set if all pending requests have been cancelled.
    var shouldCancelAllRequests = false
    
    /// Dispatch Queue used to issue custom compositor rendering work requests.
    private let renderingQueue = DispatchQueue(label: "me.shuifeng.mttransitions.renderingqueue")
    
    /// Dispatch Queue used to synchronize notifications that the composition will switch to a different render context.
    private let renderContextQueue = DispatchQueue(label: "me.shuifeng.mttransitions.rendercontextqueue")
    
    /// The current render context within which the custom compositor will render new output pixels buffers.
    private var renderContext: AVVideoCompositionRenderContext?
    
    /// Maintain the state of render context changes.
    private var internalRenderContextDidChange = false
    /// Actual state of render context changes.
    private var renderContextDidChange: Bool {
        get {
            return renderContextQueue.sync { internalRenderContextDidChange }
        }
        set (newRenderContextDidChange) {
            renderContextQueue.sync { internalRenderContextDidChange = newRenderContextDidChange }
        }
    }
    
    private lazy var renderer = MTVideoTransitionRenderer(effect: effect)
    
    /// Effect apply to video transition
    var effect: MTTransition.Effect { return .angular }
    
    override init() {
        super.init()
    }
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContextQueue.sync { renderContext = newRenderContext }
        renderContextDidChange = true
    }
    
    enum PixelBufferRequestError: Error {
        case newRenderedPixelBufferForRequestFailure
    }
    
    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
//        print("composition time \(asyncVideoCompositionRequest.compositionTime)")
        autoreleasepool {
            renderingQueue.async {
                // Check if all pending requests have been cancelled.
                if self.shouldCancelAllRequests {
                    asyncVideoCompositionRequest.finishCancelledRequest()
                } else {
                    guard let currentInstruction = asyncVideoCompositionRequest.videoCompositionInstruction as? MTVideoCompositionInstruction else {
                        return
                    }

                    let foregroundSourceBuffer = asyncVideoCompositionRequest.sourceFrame(byTrackID: currentInstruction.foregroundTrackID)
                    let backgroundSourceBuffer = asyncVideoCompositionRequest.sourceFrame(byTrackID: currentInstruction.backgroundTrackID)

                    switch (foregroundSourceBuffer, backgroundSourceBuffer) {
                    case (.some, .none):
                        guard let resultPixels = self.newRenderedPixelBuffer(asyncVideoCompositionRequest) else {
                            asyncVideoCompositionRequest.finish(with: PixelBufferRequestError.newRenderedPixelBufferForRequestFailure)
                            return
                        }
                        // The resulting pixelBuffer from Metal renderer is passed along to the request.
                        asyncVideoCompositionRequest.finish(withComposedVideoFrame: resultPixels)
                    case (.some, .some):
                        if self.renderer.effect != currentInstruction.effect {
                            self.renderer = MTVideoTransitionRenderer(effect: currentInstruction.effect)
                        }
                        guard let resultPixels = self.newRenderedPixelBufferForTransition(asyncVideoCompositionRequest) else {
                            asyncVideoCompositionRequest.finish(with: PixelBufferRequestError.newRenderedPixelBufferForRequestFailure)
                            return
                        }
                        // The resulting pixelBuffer from Metal renderer is passed along to the request.
                        asyncVideoCompositionRequest.finish(withComposedVideoFrame: resultPixels)
                    default:
                        // The resulting pixelBuffer from Metal renderer is passed along to the request.
                        asyncVideoCompositionRequest.finish(with: PixelBufferRequestError.newRenderedPixelBufferForRequestFailure)
                    }
                }
            }
        }
    }
    
    func cancelAllPendingVideoCompositionRequests() {
        /*
         Pending requests will call finishCancelledRequest, those already rendering will call
         finishWithComposedVideoFrame.
         */
        renderingQueue.sync { shouldCancelAllRequests = true }
        renderingQueue.async {
            // Start accepting requests again.
            self.shouldCancelAllRequests = false
        }
    }
    
    func factorForTimeInRange( _ time: CMTime, range: CMTimeRange) -> Float64 { /* 0.0 -> 1.0 */
        let elapsed = CMTimeSubtract(time, range.start)
        return CMTimeGetSeconds(elapsed) / CMTimeGetSeconds(range.duration)
    }

    func newRenderedPixelBuffer(_ request: AVAsynchronousVideoCompositionRequest) -> CVPixelBuffer? {
        guard let instruction = request.videoCompositionInstruction as? MTVideoCompositionInstruction else {
            return nil
        }

        guard let outputPixels = renderContext?.newPixelBuffer() else {
            return nil
        }

        guard let image = instruction.apply(request: request) else {
            return nil
        }

        MTVideoCompositor.ciContext.render(image, to: outputPixels)

        return outputPixels
    }

    func newRenderedPixelBufferForTransition(_ request: AVAsynchronousVideoCompositionRequest) -> CVPixelBuffer? {

        /*
         tweenFactor indicates how far within that timeRange are we rendering this frame. This is normalized to vary
         between 0.0 and 1.0. 0.0 indicates the time at first frame in that videoComposition timeRange. 1.0 indicates
         the time at last frame in that videoComposition timeRange.
         */
        let tweenFactor = factorForTimeInRange(request.compositionTime, range: request.videoCompositionInstruction.timeRange)

        guard let currentInstruction = request.videoCompositionInstruction as? MTVideoCompositionInstruction else {
            return nil
        }

        // Source pixel buffers are used as inputs while rendering the transition.
        guard let foregroundSourceBuffer = renderContext?.newPixelBuffer(),
              let backgroundSourceBuffer = renderContext?.newPixelBuffer() else {
                  return nil
              }

        guard let (foreground, background) = currentInstruction.makeTransitionFrame(request: request) else {
            return nil
        }

        MTVideoCompositor.ciContext.render(foreground, to: foregroundSourceBuffer)
        MTVideoCompositor.ciContext.render(background, to: backgroundSourceBuffer)

        // Destination pixel buffer into which we render the output.
        guard let dstPixels = renderContext?.newPixelBuffer() else { return nil }

        if renderContextDidChange { renderContextDidChange = false }

        // Render transition
        renderer.renderPixelBuffer(dstPixels,
                                   usingForegroundSourceBuffer:foregroundSourceBuffer,
                                   andBackgroundSourceBuffer:backgroundSourceBuffer,
                                   forTweenFactor:Float(tweenFactor))

        return dstPixels
    }
}




