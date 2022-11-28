//
//  CMTime+Extensions.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/11/28.
//

import CoreMedia
import Foundation

extension CMTime {

    static func makeLoopTime(timeRange: CMTimeRange, at: CMTime = .zero, until: CMTime) -> [(at: CMTime, timeRange: CMTimeRange)] {
        let duration = timeRange.duration
        var t = at
        var times = [(at: CMTime, timeRange: CMTimeRange)]()
        while t < until {
            let adjustedDuration = CMTimeMinimum(CMTimeSubtract(until, t), duration)
            let adjustedTimeRange = CMTimeRange(start: timeRange.start, duration: adjustedDuration)
            times.append((at: t, timeRange: adjustedTimeRange))
            t = CMTimeAdd(t, adjustedDuration)
        }
        return times
    }

}
