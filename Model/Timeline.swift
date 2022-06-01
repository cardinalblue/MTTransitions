//
//  Timeline.swift
//  MetalPetal
//
//  Created by Jim Wang on 2022/5/30.
//

import Foundation
import CoreMedia

public class Timeline {

    public init() {}

    public var renderSize: CGSize = CGSize(width: 960, height: 540)
    public var backgroundColor: CIColor = CIColor(red: 0, green: 0, blue: 0)
    public var clips: [Clip] = []
    public var transitions: [MTTransition.Effect] = []

    struct CompositionInstruction {
        /// The available time ranges for the movie clips.
        let clipTimeRanges: [CMTimeRange]

        /// The time range in which the clips should pass through.
        let passThroughTimeRanges: [CMTimeRange]

        /// The transition time range for the clips.
        let transitionTimeRanges: [CMTimeRange]

        let videoTrackIDs: [Int: CMPersistentTrackID]
    }

    private var _incrementTrackID: Int32 = 0
    private func generateNextTrackID() -> Int32 {
        _incrementTrackID += 1
        return _incrementTrackID
    }

    private func reset() {
        _incrementTrackID = 0
    }

    private func buildTracks() -> [Int: CMPersistentTrackID] {
        var videoTrackIDs: [Int: Int32] = [:]

        func getVideoTrackID(for index: Int) -> CMPersistentTrackID {
            if let trackID = videoTrackIDs[index] {
                return trackID
            }
            let trackID = generateNextTrackID()
            videoTrackIDs[index] = trackID
            return trackID
        }

        //  0 + (0 % 2 + 1) * 1000 = (0 + 1) * 1000 = 1000
        //  0 + (1 % 2 + 1) * 1000 = (1 + 1) * 1000 = 2000
        //  0 + (2 % 2 + 1) * 1000 = (0 + 1) * 1000 = 1000
        //  0 + (3 % 2 + 1) * 1000 = (1 + 1) * 1000 = 2000
        //  0 + (4 % 2 + 1) * 1000 = (0 + 1) * 1000 = 1000
        //  0 + (5 % 2 + 1) * 1000 = (1 + 1) * 1000 = 2000
        clips
            .enumerated()
            .forEach { offset, clip in
                for index in 0..<clip.numberOfVideoTracks() {
                    let trackID: Int32 = getVideoTrackID(for: index) + Int32((offset % 2 + 1) * 1000)
                    videoTrackIDs[offset] = trackID
                }
            }
        return videoTrackIDs
    }


    func build() -> CompositionInstruction {
        let semaphore = DispatchSemaphore(value: 0)
        for clip in clips {
            clip.prepare { status in
                semaphore.signal()
            }
            semaphore.wait()
        }
        // CTR -> clip time range
        // PTR -> passThrough time range
        // TTR -> transition time range
        //
        // =================================================================
        //   #     |            CTR[0]          |                  |              CTR[2]           |
        //   #                     |            CTR[1]             |
        //   #     |     PTR[0]    |   TTR[0]   |      PTR[1]      |   TTR[1]  |      PTR[2]       |
        // Track 1 |▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄|▄▄▄▄▄▄▄▄▄▄▄▄|                  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
        // Track 2 |                ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
        // Timeline
        // ------------------------------------------------------------------------------------------------>

        // Calculate transition duration
        let transitionDuration: CMTime = { () -> CMTime in
            var duration = CMTime(seconds: 2, preferredTimescale: 1000)
            // Make transitionDuration no greater than half the shortest clip duration.
            for clip in clips {
                var halfClipDuration = clip.duration
                // You can halve a rational by doubling its denominator.
                halfClipDuration.timescale *= 2
                duration = CMTimeMinimum(duration, halfClipDuration)
            }
            return duration
        }()

        // - Build start time for each clip
        var nextClipStartTime = CMTime.zero
        let clipTimeRanges: [CMTimeRange] = clips.map { clip -> CMTimeRange in
            let startTime = nextClipStartTime
            /*
             The end of this clip will overlap the start of the next by transitionDuration.
             (Note: this arithmetic falls apart if timeRangeInAsset.duration < 2 * transitionDuration.)
             */
            nextClipStartTime = CMTimeAdd(nextClipStartTime, clip.duration)
            nextClipStartTime = CMTimeSubtract(nextClipStartTime, transitionDuration)
            return CMTimeRange(start: startTime, duration: clip.duration)
        }

        // - Build pass through time for each clip

        let passThroughTimeRanges: [CMTimeRange] = clipTimeRanges.enumerated().map { index, timeRange -> CMTimeRange in
            var passThroughTimeRange = timeRange
            if index > 0 {
                passThroughTimeRange.start = CMTimeAdd(passThroughTimeRange.start, transitionDuration)
                passThroughTimeRange.duration = CMTimeSubtract(passThroughTimeRange.duration, transitionDuration)
            }
            if index + 1 < clips.count {
                passThroughTimeRange.duration = CMTimeSubtract(passThroughTimeRange.duration, transitionDuration)
            }
            return passThroughTimeRange
        }

        // - Build transition time ranges
        // TODO: check index boundary. The `transitions.count` should be equal to` clips.count - 1`.
        let transitionTimeRanges: [CMTimeRange] = clipTimeRanges[1..<clipTimeRanges.count - 2].map {
            CMTimeRange(start: $0.start, duration: transitionDuration)
        }

        // - Build tracks

        let videoTrackIDs = buildTracks()

        return CompositionInstruction(
            clipTimeRanges: clipTimeRanges,
            passThroughTimeRanges: passThroughTimeRanges,
            transitionTimeRanges: transitionTimeRanges,
            videoTrackIDs: videoTrackIDs
        )
    }

}
