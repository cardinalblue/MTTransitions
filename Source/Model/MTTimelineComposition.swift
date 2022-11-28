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
    case unavailable(clips: [Clip])
    case noCompositionTrack
}

public struct MTTimelineCompositionResult {

    public let composition: AVComposition

    public let videoComposition: AVVideoComposition?

    public let audioMix: AVAudioMix?

    init(composition: AVComposition, videoComposition: AVVideoComposition?, audioMix: AVAudioMix? = nil) {
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
    }

}

public class MTTimelineComposition {

    let timeline: Timeline

    private var composition: AVComposition?
    private var videoComposition: AVVideoComposition?
    private var audioMix: AVAudioMix?

    private let queue: DispatchQueue = DispatchQueue(label: "me.shuifeng.mttransitions.timeline_composition_queue")

    // MARK: Object lifecycle

    public init(timeline: Timeline) {
        self.timeline = timeline
    }

    public func buildPlayerItem() throws -> AVPlayerItem {
        let compositionResult = try buildComposition()
        let playerItem = AVPlayerItem(asset: compositionResult.composition)
        playerItem.videoComposition = compositionResult.videoComposition
        playerItem.audioMix = compositionResult.audioMix
        return playerItem
    }

    // MARK: - Build Composition

    public func prepare(completion: @escaping (Result<Void, Error>) -> Void) {
        let group = DispatchGroup()
        group.enter()

        timeline.clips.forEach { clip in
            group.enter()
            clip.prepare { status in
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else {
                return
            }

            let unavailableClips = self.timeline.clips.filter { !$0.isReady }

            if unavailableClips.isEmpty {
                completion(.success(Void()))
            } else {
                let error = MTTimelineCompositionError.unavailable(clips: unavailableClips)
                completion(.failure(error))
            }
        }

        group.leave()
    }

    @discardableResult
    public func buildComposition() throws -> MTTimelineCompositionResult {
        guard timeline.clips.count > 0 else {
            throw MTTimelineCompositionError.noClips
        }

        let unavailableClips = timeline.clips.filter { !$0.isReady }
        guard unavailableClips.isEmpty else {
            throw MTTimelineCompositionError.unavailable(clips: unavailableClips)
        }

        let instruction = try timeline.build()

        let composition = AVMutableComposition(urlAssetInitializationOptions: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        var audioMixInputParameters: [AVAudioMixInputParameters] = []

        try instruction
            .clipTrackInfos
            .forEach { trackInfo in
                let clip = trackInfo.clip
                let time = trackInfo.timeRange.start
                let trackID = trackInfo.trackID

                switch trackInfo.mediaType {
                case .video:
                    let resourceInfo = clip.resource.trackInfo(for: .video, at: trackInfo.index)
                    try composition.addResource(trackID: trackID, with: resourceInfo, at: time)
                case .audio:
                    let resourceInfo = clip.resource.trackInfo(for: .audio, at: trackInfo.index)
                    try composition.addResource(trackID: trackID, with: resourceInfo, at: time)
                case .backgroundAudio:
                    let resourceInfo = clip.resource.trackInfo(for: .audio, at: trackInfo.index)
                    let endTime = trackInfo.timeRange.end
                    try composition.addResource(trackID: trackID, with: resourceInfo,
                                                at: time, timeRange: resourceInfo.selectedTimeRange, until: endTime)

                    let track = composition.track(withTrackID: trackID)
                    let inputParameter = AVMutableAudioMixInputParameters(track: track)

                    let fadeDuration = CMTime(seconds: 1.5, preferredTimescale: 10000)
                    let fadeInTimeRange = CMTimeRange(start: time, duration: fadeDuration)
                    let fadeOutTimeRange = CMTimeRange(start: endTime - fadeDuration, duration: fadeDuration)
                    inputParameter.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: fadeInTimeRange)
                    inputParameter.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: fadeOutTimeRange)
                    audioMixInputParameters.append(inputParameter)
                }
            }

        let videoComposition = buildVideoComposition(instruction: instruction, composition: composition)

        let audioMix = { () -> AVAudioMix? in
            if audioMixInputParameters.isEmpty {
                return nil
            }
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixInputParameters
            return audioMix
        }()

        return MTTimelineCompositionResult(composition: composition, videoComposition: videoComposition, audioMix: audioMix)
    }

    private enum CompositorType {
        case avfoundation
        case transition
        case timeline
    }

    private func buildVideoComposition(instruction: Timeline.CompositionInstruction, composition: AVComposition) -> AVVideoComposition? {
        let compositorType = CompositorType.timeline

        let videoComposition = AVMutableVideoComposition()
        switch compositorType {
        case .avfoundation:
            break
        case .transition:
            videoComposition.customVideoCompositorClass = MTVideoCompositor.self
        case .timeline:
            videoComposition.customVideoCompositorClass = MTTimelineVideoCompositor.self
        }

        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps.
        videoComposition.renderSize = timeline.renderSize

        // - Build passthrough instructions
        let passthroughCompositionInstructions: [AVVideoCompositionInstructionProtocol] = instruction
            .passThroughTrackInfos
            .map { trackInfo -> AVVideoCompositionInstructionProtocol in
                let clip = trackInfo.clip
                let trackID: Int32 = trackInfo.trackID
                let trackIDs: [NSNumber] = [NSNumber(value: trackID)]
                let timeRange = trackInfo.timeRange
                let videoCompositionProvider = clip
                let videoInstruction = MTTimelineVideoCompositionInstruction(theSourceTrackIDs: trackIDs, forTimeRange: timeRange)
                videoInstruction.layerInstructions = [
                    MTTimelineVideoCompositionLayerInstruction(
                        trackID: trackID, videoCompositionProvider: videoCompositionProvider
                    )
                ]
                return videoInstruction
            }

        // - Build transition instruction
        let transitionCompositionInstructions: [AVVideoCompositionInstructionProtocol] = instruction
            .transitionTrackInfos.compactMap { trackInfo -> AVVideoCompositionInstructionProtocol? in
                let timeRange = trackInfo.timeRange
                let fromClip = trackInfo.from.clip
                let toClip = trackInfo.to.clip
                let transitionEffect = trackInfo.effect

                let foregroundTrackID: Int32 = trackInfo.from.trackID
                let backgroundTrackID: Int32 = trackInfo.to.trackID
                let trackIDs: [NSNumber] = [
                    NSNumber(value: foregroundTrackID),
                    NSNumber(value: backgroundTrackID)
                ]
                let foregroundVideoCompositionProvider = fromClip
                let backgroundVideoCompositionProvider = toClip
                let videoInstruction = MTTimelineVideoCompositionInstruction(theSourceTrackIDs: trackIDs, forTimeRange: timeRange)
                videoInstruction.transitionEffect = transitionEffect
                videoInstruction.layerInstructions = [
                    MTTimelineVideoCompositionLayerInstruction(
                        trackID: foregroundTrackID, videoCompositionProvider: foregroundVideoCompositionProvider
                    ),
                    MTTimelineVideoCompositionLayerInstruction(
                        trackID: backgroundTrackID, videoCompositionProvider: backgroundVideoCompositionProvider
                    )
                ]
                return videoInstruction
            }

        videoComposition.instructions = (passthroughCompositionInstructions + transitionCompositionInstructions)
            .sorted(by: { $0.timeRange.start < $1.timeRange.start })

        return videoComposition
    }
}

extension CMTimeRange: CustomStringConvertible {

    public var description: String {
        String(format: "start: %.2fs, duration: %.2fs", start.seconds, duration.seconds)
    }
    
}
