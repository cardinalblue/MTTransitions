//
//  Timeline.swift
//  MetalPetal
//
//  Created by Jim Wang on 2022/5/30.
//

import Foundation
import CoreMedia

public protocol TransitionProvider {
    func transition(for index: Int) -> (effect: MTTransition.Effect, duration: CMTime)?
}

public struct DefaultTransitionProvider: TransitionProvider {

    let transition: (effect: MTTransition.Effect, duration: CMTime)

    public init(transition: (effect: MTTransition.Effect, duration: CMTime)) {
        self.transition = transition
    }

    public init(effect: MTTransition.Effect = .none, seconds: TimeInterval = 0) {
        self.transition = (effect, CMTime(seconds: seconds, preferredTimescale: 1000))
    }

    public func transition(for index: Int) -> (effect: MTTransition.Effect, duration: CMTime)? {
        transition
    }

}

public class Timeline {

    public init() {}

    public var renderSize: CGSize = CGSize(width: 960, height: 540)
    public var backgroundColor: CIColor = CIColor(red: 0, green: 0, blue: 0)
    public var clips: [Clip] = []
    public var backgroundAudioClip: Clip? // This clip will only use audio track
    public var transitionProvider: TransitionProvider? = DefaultTransitionProvider()

    struct CompositionInstruction {
        /// The available time ranges for the movie clips (video and audio).
        let clipTrackInfos: [TrackInfo]

        /// The time range in which the clips should pass through.
        let passThroughTrackInfos: [TrackInfo]

        /// The transition time range for the clips.
        let transitionTrackInfos: [TransitionTrackInfo]

//        var description: String {
//            """
//            clipTimeRanges: \(clipTimeRanges)
//            passThroughTimeRanges: \(passThroughTimeRanges)
//            transitionTimeRanges: \(transitionTimeRanges)
//            videoTrackIDs: \(videoTrackIDs)
//            """
//        }

    }

    func build() throws -> CompositionInstruction {
        // TODO: check index boundary. The `transitions.count` should be equal to` clips.count - 1`.

        // CTR -> clip time range
        // PTR -> passThrough time range
        // TTR -> transition time range
        //
        // =================================================================
        //   #     |            CTR[0]          |                  |              CTR[2]           |
        //   #                     |                  CTR[1]                   |
        //   #     |     PTR[0]    |   TTR[0]   |      PTR[1]      |   TTR[1]  |      PTR[2]       |
        // Track 1 |▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄|▄▄▄▄▄▄▄▄▄▄▄▄|                  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
        // Track 2 |                ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
        // Timeline
        // ------------------------------------------------------------------------------------------------>

        // Calculate transition duration
        var transitionTimeInfo: [Int: CMTime] = [:]
        (0..<clips.count - 1).forEach { transitionIndex in
            guard let transition = transitionProvider?.transition(for: transitionIndex) else {
                transitionTimeInfo[transitionIndex] = CMTime.zero
                return
            }
            let duration = transition.duration
            transitionTimeInfo[transitionIndex] = duration
        }

        // - Build start time for each clip
        var nextClipStartTime = CMTime.zero
        let clipTimeRanges: [CMTimeRange] = clips.enumerated().map { index, clip -> CMTimeRange in
            let startTime = nextClipStartTime
            /*
             The end of this clip will overlap the start of the next by transitionDuration.
             (Note: this arithmetic falls apart if timeRangeInAsset.duration < 2 * transitionDuration.)
             */
            let transitionDuration = transitionTimeInfo[index, default: CMTime.zero]

            nextClipStartTime = CMTimeAdd(nextClipStartTime, clip.duration)
            nextClipStartTime = CMTimeSubtract(nextClipStartTime, transitionDuration)
            return CMTimeRange(start: startTime, duration: clip.duration)
        }

        // - Build pass through time for each clip

        let passthroughTimeRanges: [CMTimeRange] = clipTimeRanges.enumerated().map { index, timeRange -> CMTimeRange in
            let transitionDurationFront = transitionTimeInfo[index - 1, default: CMTime.zero]
            let transitionDurationBack = transitionTimeInfo[index, default: CMTime.zero]

            var passThroughTimeRange = timeRange
            // Adjust time range for front transition
            if index > 0 {
                passThroughTimeRange.start = CMTimeAdd(passThroughTimeRange.start, transitionDurationFront)
                passThroughTimeRange.duration = CMTimeSubtract(passThroughTimeRange.duration, transitionDurationFront)
            }
            // Adjust time range for back transition
            if index < clips.count - 1 {
                passThroughTimeRange.duration = CMTimeSubtract(passThroughTimeRange.duration, transitionDurationBack)
            }
            return passThroughTimeRange
        }

        // - Build transition time ranges
        let transitionTimeRanges: [CMTimeRange] = { () -> [CMTimeRange] in
            guard clipTimeRanges.count > 1 else {
                return []
            }
            return clipTimeRanges[1..<clipTimeRanges.count].enumerated().map { index, timeRange -> CMTimeRange in
                let transitionDuration = transitionTimeInfo[index, default: CMTime.zero]
                return CMTimeRange(start: timeRange.start, duration: transitionDuration)
            }
        }()

        // - Build tracks

        func makeTrackID(trackIndex: Int, clipIndex: Int, mediaType: TrackInfo.MediaType) -> CMPersistentTrackID {
            switch mediaType {
            case .video:
                return Int32(trackIndex) + Int32((clipIndex % 2 + 1) * 100)
            case .audio:
                return Int32(trackIndex) + Int32((clipIndex % 2 + 1) * 1000)
            case .backgroundAudio:
                return Int32(trackIndex) + 10
            }
        }

        // - Track Info for clips. Use `var` here for set up backgroundAudio later.
        var clipTrackInfos: [TrackInfo] = zip(clips, clipTimeRanges)
            .enumerated()
            .flatMap { offset, info -> [TrackInfo] in
                let (clip, timeRange) = info
                var trackInfos = [TrackInfo]()
                // Video
                for index in 0..<clip.numberOfVideoTracks() {
                    let trackID = makeTrackID(trackIndex: index, clipIndex: offset, mediaType: .video)
                    let trackInfo = TrackInfo(clip: clip, index: index, mediaType: .video, trackID: trackID, timeRange: timeRange)
                    trackInfos.append(trackInfo)
                }

                // Audio
                for index in 0..<clip.numberOfAudioTracks() {
                    let trackID = makeTrackID(trackIndex: index, clipIndex: offset, mediaType: .audio)
                    let trackInfo = TrackInfo(clip: clip, index: index, mediaType: .audio, trackID: trackID, timeRange: timeRange)
                    trackInfos.append(trackInfo)
                }
                return trackInfos
            }

        // - Track Info for passthroughs
        let passthroughTrackInfos: [TrackInfo] = zip(clips, passthroughTimeRanges)
            .enumerated()
            .flatMap { offset, info -> [TrackInfo] in
                let (clip, timeRange) = info
                var trackInfos = [TrackInfo]()
                for index in 0..<clip.numberOfVideoTracks() {
                    let trackID = makeTrackID(trackIndex: index, clipIndex: offset, mediaType: .video)
                    let trackInfo = TrackInfo(clip: clip, index: index, mediaType: .video, trackID: trackID, timeRange: timeRange)
                    trackInfos.append(trackInfo)
                }
                return trackInfos
            }

        // - Track Info for transitions
        let transitionTrackInfos = zip(clips.pairwise() , transitionTimeRanges)
            .enumerated()
            .compactMap { offset, info -> TransitionTrackInfo? in
                let (clips, timeRange) = info
                guard timeRange.duration != CMTime.zero else {
                    return nil
                }
                let effect = transitionProvider?.transition(for: offset)?.effect ?? .none
                // Apply transition on the main track which the index should be 0
                let fromTrackID = makeTrackID(trackIndex: 0, clipIndex: offset, mediaType: .video)
                let toTrackID = makeTrackID(trackIndex: 0, clipIndex: offset + 1, mediaType: .video)
                let trackInfo = TransitionTrackInfo(
                    from: (clips.0, fromTrackID),
                    to: (clips.1, toTrackID),
                    effect: effect,
                    timeRange: timeRange
                )
                return trackInfo
            }

        // - Track Info for background audio
        if let backgroundAudioClip = backgroundAudioClip {
            let start = clipTimeRanges.first!.start
            let end = clipTimeRanges.last!
            let timeRange = CMTimeRange(start: start, duration: end.end)

            for index in 0..<backgroundAudioClip.numberOfAudioTracks() {
                let trackID = makeTrackID(trackIndex: index, clipIndex: 0, mediaType: .backgroundAudio)
                let trackInfo = TrackInfo(
                    clip: backgroundAudioClip, index: index, mediaType: .backgroundAudio, trackID: trackID, timeRange: timeRange
                )
                clipTrackInfos.append(trackInfo)
            }
        }

        return CompositionInstruction(
            clipTrackInfos: clipTrackInfos,
            passThroughTrackInfos: passthroughTrackInfos,
            transitionTrackInfos: transitionTrackInfos
        )
    }

}

// MARK: Track Info

struct TrackInfo {

    enum MediaType {
        case video
        case audio
        case backgroundAudio
    }

    let clip: Clip
    let index: Int
    let mediaType: MediaType
    let trackID: Int32
    let timeRange: CMTimeRange
}

struct TransitionTrackInfo {
    let from: (clip: Clip, trackID: Int32)
    let to: (clip: Clip, trackID: Int32)
    let effect: MTTransition.Effect
    let timeRange: CMTimeRange
}
