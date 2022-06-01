//
//  MTTimelineComposition.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/5/30.
//

import AVFoundation
import Foundation

public enum MTTimelineCompositionError: Error {
    case noClips
}

public class MTTimelineComposition {

    let timeline: Timeline

    private var composition: AVComposition?
    private var videoComposition: AVVideoComposition?
    private var audioMix: AVAudioMix?

    // MARK: Object lifecycle

    public init(timeline: Timeline) {
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

        print(instruction)

        let pair = zip(timeline.clips, instruction.clipTimeRanges)

        pair.enumerated()
            .forEach { offset, info in
                let (clip, timeRange) = info
                for index in 0..<clip.numberOfVideoTracks() {
                    let trackID: Int32 = instruction.videoTrackIDs[offset % 2]!
                    print("set up clip \(clip.identifier) index: \(index) trackID: \(trackID) ")
                    _ = clip.videoCompositionTrack(at: index, for: composition, preferredTrackID: trackID, timeRange: timeRange)
                }
            }

        let videoComposition = buildVideoComposition(instruction: instruction, composition: composition)

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

    private func buildVideoComposition(instruction: Timeline.CompositionInstruction, composition: AVComposition) -> AVVideoComposition? {
        let useCustomVideoCompositorClass = true

        let videoComposition = AVMutableVideoComposition()
        if useCustomVideoCompositorClass {
            videoComposition.customVideoCompositorClass = MTVideoCompositor.self
        }
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps.
        videoComposition.renderSize = timeline.renderSize

        // - Build passThrough instructions
        let passThroughCompositionInstructions: [AVVideoCompositionInstructionProtocol] = instruction
            .passThroughTimeRanges.enumerated().map { index, timeRange -> AVVideoCompositionInstructionProtocol in
                if useCustomVideoCompositorClass {
                    let trackID: Int32 = instruction.videoTrackIDs[index % 2]!
                    let videoInstruction = MTVideoCompositionInstruction(sourceTrackID: trackID, forTimeRange: timeRange)
                    print("passthrough: \(timeRange)")
                    videoInstruction.configuration = VideoConfiguration()
                    videoInstruction.foregroundTrackID = trackID
                    return videoInstruction
                } else {
                    // Pass through clip i.
                    let trackID: Int32 = instruction.videoTrackIDs[index % 2]!
                    let assetTrack = composition.track(withTrackID: trackID)!
                    let passThroughInstruction = AVMutableVideoCompositionInstruction()
                    passThroughInstruction.timeRange = timeRange
                    let passThroughLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: assetTrack)
                    passThroughInstruction.layerInstructions = [passThroughLayer]
                    return passThroughInstruction
                }
            }

        // - Build transition instruction

        let transitionCompositionInstructions: [AVVideoCompositionInstructionProtocol] = instruction
            .transitionTimeRanges.map { timeRange -> AVVideoCompositionInstructionProtocol in
                if useCustomVideoCompositorClass {
                    let foregroundTrackID: Int32 = instruction.videoTrackIDs[0]!
                    let backgroundTrackID: Int32 = instruction.videoTrackIDs[1]!
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
                } else {
                    let foregroundTrackID: Int32 = instruction.videoTrackIDs[0]!
                    let backgroundTrackID: Int32 = instruction.videoTrackIDs[1]!

                    let fromAssetTrack = composition.track(withTrackID: foregroundTrackID)!
                    let toAssetTrack = composition.track(withTrackID: backgroundTrackID)!

                    let transitionInstruction = AVMutableVideoCompositionInstruction()
                    print("transition: \(timeRange)")
                    transitionInstruction.timeRange = timeRange
                    let fromLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: fromAssetTrack)
                    let toLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: toAssetTrack)
                    transitionInstruction.layerInstructions = [fromLayer, toLayer]
                    return transitionInstruction
                }
            }

        videoComposition.instructions = (passThroughCompositionInstructions + transitionCompositionInstructions)
            .sorted(by: { $0.timeRange.start < $1.timeRange.start })

        return videoComposition
    }
}


private class TrackInfo<T> {
    var track: AVCompositionTrack
    var info: T
    init(track: AVCompositionTrack, info: T) {
        self.track = track
        self.info = info
    }
}

extension CMTimeRange: CustomStringConvertible {

    public var description: String {
        String(format: "start: %.2fs, duration: %.2fs", start.seconds, duration.seconds)
    }
    
}
