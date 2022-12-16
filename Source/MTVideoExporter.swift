//
//  MTVideoExporter.swift
//  MTTransitions
//
//  Created by xushuifeng on 2020/3/23.
//

import AVFoundation

public typealias MTVideoExporterCompletion = (Error?) -> Void

public class MTVideoExporter {
    
    private let composition: AVComposition

    private let exportSession: AVAssetExportSession
    
    public convenience init(transitionResult: MTVideoTransitionResult, presetName: String = AVAssetExportPresetHighestQuality) throws {
        try self.init(composition: transitionResult.composition, videoComposition: transitionResult.videoComposition, presetName: presetName)
    }

    public init(
        composition: AVComposition,
        videoComposition: AVVideoComposition?,
        audioMix: AVAudioMix? = nil,
        presetName: String = AVAssetExportPresetHighestQuality,
        metadata: [AVMetadataItem]? = nil
    ) throws {
        self.composition = composition
        guard let session = AVAssetExportSession(asset: composition, presetName: presetName) else {
            fatalError("Can not create AVAssetExportSession, please check composition")
        }
        self.exportSession = session
        self.exportSession.videoComposition = videoComposition
        self.exportSession.audioMix = audioMix
        self.exportSession.metadata = metadata
    }
    
    /// Export the composition to local file.
    /// - Parameters:
    ///   - fileURL: The output fileURL.
    ///   - outputFileType: The output file type. `mp4` by default.
    ///   - completion: Export completion callback.
    @discardableResult
    public func export(to fileURL: URL, outputFileType: AVFileType = .mp4, completion: @escaping MTVideoExporterCompletion) -> AVAssetExportSession {
        
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        if fileExists {
            do {
                try FileManager.default.removeItem(atPath: fileURL.path)
            } catch {
                print("An error occured deleting the file: \(error)")
            }
        }
        exportSession.outputURL = fileURL
        exportSession.outputFileType = outputFileType
        
        let startTime = CMTimeMake(value: 0, timescale: 1)
        let timeRange = CMTimeRangeMake(start: startTime, duration: composition.duration)
        exportSession.timeRange = timeRange

        let es = exportSession
        exportSession.exportAsynchronously(completionHandler: { [es] in
            // Keep it alive and make sure the internal exportSession's lifecycle won't deallocate from background thread.
            DispatchQueue.main.async {
                completion(es.error)
                _ = es
            }
        })
        return exportSession
    }
}
