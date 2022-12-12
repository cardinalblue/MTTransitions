//
//  AnimatedOutputVideoCompositor.swift
//  CustomVideoCompositor
//
//  Created by yyjim on 2018/7/27.
//  Copyright © 2018 Clay Garrett. All rights reserved.
//

import UIKit
import VideoToolbox
import AVFoundation

class AnimatedOutputVideoCompositor: NSObject, AVVideoCompositing {
    private let context = CIContext(options: nil)

    let sourcePixelBufferAttributes: [String: Any]? = [
        String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
        String(kCVPixelBufferOpenGLESCompatibilityKey): true,
        String(kCVPixelBufferMetalCompatibilityKey): true
    ]

    let requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
        String(kCVPixelBufferOpenGLESCompatibilityKey): true,
        String(kCVPixelBufferMetalCompatibilityKey): true
    ]

    // MARK: AVVideoCompositing

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        // called for every frame
        // assuming there's a single video track. account for more complex scenarios as you need to
        let destination = request.renderContext.newPixelBuffer()!
        let instruction = request.videoCompositionInstruction as! AnimatedOutputCompositionInstruction
        let videoClips = instruction.videoClips

        let sortedTrackIDs = request.sourceTrackIDs.sorted(by: { $0.int32Value > $1.int32Value })
        for (index, videoClip) in videoClips.sorted(by: { $0.trackID > $1.trackID }).enumerated() {
            guard index < sortedTrackIDs.count else {
                continue
            }
            let trackID = sortedTrackIDs[index].int32Value
            if let videoLayer = videoClip.layer, videoClip.trackID == trackID {
                let videoSourceBuffer = request.sourceFrame(byTrackID: trackID)!
                // NOTE: The Core Image rotation is opposite.
                // let transform = CGAffineTransform(rotationAngle: -videoClip.transform.rotation)
                // https://stackoverflow.com/questions/29967700/coreimage-coordinate-system
                var transform = videoClip.transform
                transform.b *= -1
                transform.c *= -1
                let videoimage = videoSourceBuffer.createCGImage(transform: transform, context: context)
                DispatchQueue.main.sync {
                    videoLayer.contents = videoimage
                }
            }
        }

        request.finish(withComposedVideoFrame: destination)
    }
}

private extension CVPixelBuffer {

    func createCGImage(transform: CGAffineTransform, context inputContext: CIContext?) -> CGImage? {
        if transform == CGAffineTransform.identity {
            var cgImage: CGImage?
            // This is faster than create cgImage by CIContext, but it can't apply transform
            VTCreateCGImageFromCVPixelBuffer(self, options: nil, imageOut: &cgImage)
            return cgImage
        } else {
            let ciImage = CIImage(cvImageBuffer: self)
            let filter = CIFilter(name: "CIAffineTransform")!
            filter.setDefaults()
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(NSValue(cgAffineTransform: transform), forKey: "inputTransform")

            let context = inputContext ?? CIContext(options: nil)
            let outputImage = filter.outputImage
            let cgImage = context.createCGImage(outputImage!, from: (outputImage?.extent)!)
            return cgImage
        }
    }
}
