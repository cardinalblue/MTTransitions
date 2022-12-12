//
//  AnimatedOutputCompositionInstruction.swift
//  PicCollage
//
//  Created by yyjim on 2018/7/27.
//

import Foundation
import AVFoundation

class AnimatedOutputCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let videoClips: [VideoClip]

    // The following 5 items are required for the protocol
    // See information on them here:
    // https://developer.apple.com/reference/avfoundation/avvideocompositioninstructionprotocol
    // set the correct values for your specific use case

    /* Indicates the timeRange during which the instruction is effective. Note requirements for the timeRanges of instructions described in connection with AVVideoComposition's instructions key above. */
    var timeRange: CMTimeRange

    /* If NO, indicates that post-processing should be skipped for the duration of this instruction.
     See +[AVVideoCompositionCoreAnimationTool videoCompositionToolWithPostProcessingAsVideoLayer:inLayer:].*/
    var enablePostProcessing = true

    /* If YES, rendering a frame from the same source buffers and the same composition instruction at 2 different
     compositionTime may yield different output frames. If NO, 2 such compositions would yield the
     same frame. The media pipeline may me able to avoid some duplicate processing when containsTweening is NO */
    var containsTweening = true

    /* List of video track IDs required to compose frames for this instruction. If the value of this property is nil, all source tracks will be considered required for composition */
    var requiredSourceTrackIDs: [NSValue]?

    /* If for the duration of the instruction, the video composition result is one of the source frames, this property should
     return the corresponding track ID. The compositor won't be run for the duration of the instruction and the proper source
     frame will be used instead. The dimensions, clean aperture and pixel aspect ratio of the source buffer will be
     matched to the required values automatically */
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid // if not a passthrough instruction

    init(timeRange: CMTimeRange, videoClips: [VideoClip]) {
        self.timeRange  = timeRange
        self.videoClips = videoClips
    }
}
