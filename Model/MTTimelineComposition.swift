//
//  MTTimelineComposition.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/30.
//

import AVFoundation
import Foundation

enum MTTimelineCompositionError: Error {
    case noClips
}

class MTTimelineComposition {

    let timeline: Timeline

    private var composition: AVComposition?
    private var videoComposition: AVVideoComposition?
    private var audioMix: AVAudioMix?

    // MARK: Object lifecycle

    init(timeline: Timeline) {
        self.timeline = timeline
    }

    public func buildPlayerItem() throws -> AVPlayerItem {
        let (composition, videoComposition) = try buildComposition()
        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComposition
        //playerItem.audioMix = buildAudioMix()
        return playerItem
    }

    // MARK: - Build Composition

    @discardableResult
    public func buildComposition() throws -> (AVComposition, AVVideoComposition?) {
        guard timeline.clips.count > 0 else {
            throw MTTimelineCompositionError.noClips
        }

        let composition = AVMutableComposition(urlAssetInitializationOptions: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let instruction = timeline.build()

        timeline.clips
            .enumerated()
            .forEach { index, clip in
                for index in 0..<clip.numberOfVideoTracks() {
                    let trackID = instruction.videoTrackIDs[index]!
                    _ = clip.videoCompositionTrack(at: index, for: composition, preferredTrackID: trackID)
                }
            }

        let videoComposition = buildVideoComposition(instruction: instruction)

        return (composition, videoComposition)
//        timeline.videoChannel.enumerated().forEach({ (offset, provider) in
//            for index in 0..<provider.numberOfVideoTracks() {
//                let trackID: Int32 = getVideoTrackID(for: index) + Int32((offset % 2 + 1) * 1000)
//                if let compositionTrack = provider.videoCompositionTrack(for: composition, at: index, preferredTrackID: trackID) {
//                    let info = mainVideoTrackInfo.first(where: { $0.track == compositionTrack })
//                    if let info = info {
//                        info.info.append(provider)
//                    } else {
//                        let info = TrackInfo.init(track: compositionTrack, info: [provider])
//                        mainVideoTrackInfo.append(info)
//                    }
//                }
//            }
//        })
//        return composition
    }

    public func buildVideoComposition(instruction: Timeline.CompositionInstruction) -> AVVideoComposition? {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = MTVideoCompositor.self
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps.
        videoComposition.renderSize = timeline.renderSize
        videoComposition.instructions = []

        // - Build passThrough instructions
        let passThroughCompositionInstructions: [AVVideoCompositionInstructionProtocol] = instruction
            .passThroughTimeRanges.map { timeRange -> AVVideoCompositionInstructionProtocol in
                let trackID: Int32 = 0
                let videoInstruction = MTVideoCompositionInstruction(sourceTrackID: 0, forTimeRange: timeRange)
                videoInstruction.configuration = VideoConfiguration()
                videoInstruction.foregroundTrackID = trackID
                return videoInstruction
            }

        // - Build transition instruction

        let transitionCompositionInstructions: [AVVideoCompositionInstructionProtocol] = instruction
            .transitionTimeRanges.map { timeRange -> AVVideoCompositionInstructionProtocol in
                let foregroundTrackID: Int32 = 0
                let backgroundTrackID: Int32 = 0
                let trackIDs: [NSNumber] = [
                    NSNumber(value: foregroundTrackID),
                    NSNumber(value: backgroundTrackID)
                ]
                let videoInstruction = MTVideoCompositionInstruction(theSourceTrackIDs: trackIDs, forTimeRange: timeRange)
                videoInstruction.effect = MTTransition.Effect.bounce
                videoInstruction.configuration = VideoConfiguration()
                // First track -> Foreground track while compositing.
                videoInstruction.foregroundTrackID = foregroundTrackID
                // Second track -> Background track while compositing.
                videoInstruction.backgroundTrackID = backgroundTrackID
                return videoInstruction
            }

        videoComposition.instructions = passThroughCompositionInstructions + transitionCompositionInstructions

        return videoComposition
    }
//    public func buildVideoComposition() -> AVVideoComposition? {
//        // Add transition from clip[i] to clip[i + 1]
//        let videoComposition = AVMutableVideoComposition()
//        videoComposition.customVideoCompositorClass = MTVideoCompositor.self
//        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps.
//        videoComposition.renderSize = timeline.renderSize
//        videoComposition.instructions = []
//
//        var alternatingIndex = 0
//        var instructions = [Any]()
//
//        for index in 0..<timeline.clips.count {
//            alternatingIndex = index % 2
//
//            let trackID = compositionVideoTracks[alternatingIndex].trackID
//            let timeRange = passThroughTimeRanges[index]
//            let videoInstruction = MTVideoCompositionInstruction(sourceTrackID: trackID, forTimeRange: timeRange)
//            videoInstruction.foregroundTrackID = trackID
//            videoInstruction.configuration = VideoConfiguration()
//            instructions.append(videoInstruction)
//
//            if index + 1 < clips.count {
//                let foregroundTrackID: Int32 = 0
//                let backgroundTrackID: Int32 = 0
//                let trackIDs: [NSNumber] = [
//                    NSNumber(value: compositionVideoTracks[0].trackID),
//                    NSNumber(value: compositionVideoTracks[1].trackID)
//                ]
//                let timeRange = transitionTimeRanges[index]
//                let videoInstruction = MTVideoCompositionInstruction(theSourceTrackIDs: trackIDs, forTimeRange: timeRange)
//                videoInstruction.effect = timeline.transitions[index]
//                // First track -> Foreground track while compositing.
//                videoInstruction.foregroundTrackID = compositionVideoTracks[alternatingIndex].trackID
//                // Second track -> Background track while compositing.
//                videoInstruction.backgroundTrackID = compositionVideoTracks[1 - alternatingIndex].trackID
//                instructions.append(videoInstruction)
//            }
//        }

//        videoComposition.instructions =
//
//        return videoComposition
//    }

//    private func makeTransitionInstructions(videoComposition: AVMutableVideoComposition,
//                                            compositionVideoTracks: [AVMutableCompositionTrack]) -> [Any] {
//        var alternatingIndex = 0
//        var instructions = [Any]()
//
//        for index in 0 ..< clips.count {
//            alternatingIndex = index % 2
//            if videoComposition.customVideoCompositorClass != nil {
//                let trackID = compositionVideoTracks[alternatingIndex].trackID
//                let timeRange = passThroughTimeRanges[index]
//                let videoInstruction = MTVideoCompositionInstruction(sourceTrackID: trackID, forTimeRange: timeRange)
//                videoInstruction.foregroundTrackID = trackID
//                videoInstruction.configuration = VideoConfiguration()
//                //                let videoInstruction = MTVideoCompositionInstruction(thePassthroughTrackID: trackID, forTimeRange: timeRange)
//                instructions.append(videoInstruction)
//            } else {
//                // Pass through clip i.
//                let passThroughInstruction = AVMutableVideoCompositionInstruction()
//                passThroughInstruction.timeRange = passThroughTimeRanges[index]
//                let passThroughLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTracks[alternatingIndex])
//                passThroughInstruction.layerInstructions = [passThroughLayer]
//                instructions.append(passThroughInstruction)
//            }
//
//            // Add transition from clip[i] to clip[i + 1]
//            if index + 1 < clips.count {
//                if videoComposition.customVideoCompositorClass != nil {
//                    let trackIDs: [NSNumber] = [
//                        NSNumber(value: compositionVideoTracks[0].trackID),
//                        NSNumber(value: compositionVideoTracks[1].trackID)
//                    ]
//                    let timeRange = transitionTimeRanges[index]
//                    let videoInstruction = MTVideoCompositionInstruction(theSourceTrackIDs: trackIDs, forTimeRange: timeRange)
//                    videoInstruction.effect = effects[index]
//                    // First track -> Foreground track while compositing.
//                    videoInstruction.foregroundTrackID = compositionVideoTracks[alternatingIndex].trackID
//                    // Second track -> Background track while compositing.
//                    videoInstruction.backgroundTrackID =
//                    compositionVideoTracks[1 - alternatingIndex].trackID
//                    instructions.append(videoInstruction)
//                } else {
//                    let transitionInstruction = AVMutableVideoCompositionInstruction()
//                    transitionInstruction.timeRange = transitionTimeRanges[index]
//                    let fromLayer =
//                    AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTracks[alternatingIndex])
//                    let toLayer =
//                    AVMutableVideoCompositionLayerInstruction(assetTrack:compositionVideoTracks[1 - alternatingIndex])
//                    transitionInstruction.layerInstructions = [fromLayer, toLayer]
//                    instructions.append(transitionInstruction)
//                }
//            }
//        }
//        return instructions
//    }
}


private class TrackInfo<T> {
    var track: AVCompositionTrack
    var info: T
    init(track: AVCompositionTrack, info: T) {
        self.track = track
        self.info = info
    }
}
