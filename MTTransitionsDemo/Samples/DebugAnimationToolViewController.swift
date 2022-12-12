//
//  DebugAnimationToolViewController.swift
//  MTTransitionsDemo
//
//  Created by Jim Wang on 2022/12/12.
//  Copyright © 2022 xu.shuifeng. All rights reserved.
//

import Photos
import Combine
import MTTransitions
import Foundation

private let _queue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "com.cardinalblue.piccollage.multiple_collage_exporter"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 1
    return queue
}()

typealias AVComponents = (
    composition: AVMutableComposition,
    videoComposition: AVMutableVideoComposition,
    audioMix: AVMutableAudioMix?
)

public extension CMTime {

    static func loopTime(timeRange: CMTimeRange, until: CMTime, block: (_ at: CMTime, _ timeRange: CMTimeRange) -> Void) {
        var t = CMTime.zero
        let duration = timeRange.duration
        while t < until {
            let adjustedDuration = CMTimeMinimum(CMTimeSubtract(until, t), duration)
            let adjustedTimeRange = CMTimeRange(start: timeRange.start, duration: adjustedDuration)
            block(t, adjustedTimeRange)
            t = CMTimeAdd(t, adjustedDuration)
        }
    }

    static func loopTime(offset: CMTime, length: CMTime, until: CMTime, block: (CMTime, CMTime) -> Void) {
        var t = CMTime.zero
        var offset = CMTimeMinimum(offset, length)
        while t < until {
            block(offset, t)
            offset = CMTime.zero
            t = CMTimeAdd(t, CMTimeSubtract(length, offset))
        }
    }

}

class VideoClip: NSObject {
    let asset: AVAsset
    let isMuted: Bool
    let timeRange: CMTimeRange
    let layer: CALayer?
    let transform: CGAffineTransform
    var trackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    init(asset: AVAsset, transform: CGAffineTransform, timeRange: CMTimeRange, isMuted: Bool, layer: CALayer? = nil) {
        self.asset = asset
        self.transform = transform
        self.timeRange = timeRange
        self.isMuted = isMuted
        self.layer = layer
        super.init()
    }
}

class DebugAnimationToolViewController: UIViewController {

    var queue: OperationQueue {
        _queue
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()
    }

    private func setupNavigationBar() {
        let exportButton = UIBarButtonItem(title: "Export", style: .plain, target: self, action: #selector(handleExportButtonClicked))
        navigationItem.rightBarButtonItem = exportButton
    }

    @objc
    private func handleExportButtonClicked() {
        make()
    }

    private func make() {
        let url = Bundle.main.url(forResource: "temp", withExtension: "mp4")!
        let avasset = AVURLAsset(url: url)
        let duration = CMTime(value: Int64(10 * 600), timescale: 600)
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        let videoClip = VideoClip(
            asset: avasset,
            transform: CGAffineTransform.identity,
            timeRange: timeRange,
            isMuted: true
        )
        let avComponents = createCompositions(
            videoClips: [videoClip], size: CGSize(width: 960, height: 960), duration: 10
        )!

        let op1 = ExportOp(avComponents: avComponents, url: createCleanFileURL(fileName: "\(UUID().uuidString).mp4"), superview: view)
        let op2 = ExportOp(avComponents: avComponents, url: createCleanFileURL(fileName: "\(UUID().uuidString).mp4"), superview: view)
        let op3 = ExportOp(avComponents: avComponents, url: createCleanFileURL(fileName: "\(UUID().uuidString).mp4"), superview: view)

        queue.addOperation(op1)
        queue.addOperation(op2)
        queue.addOperation(op3)
    }

    private func createCleanFileURL(fileName: String) -> URL {
        let fileManager = FileManager.default
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let videoOutputURL = directory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: videoOutputURL.path) {
            do {
                try FileManager.default.removeItem(atPath: videoOutputURL.path)
            } catch {
                fatalError("Unable to delete file: \(error) : \(#function).")
            }
        }
        return videoOutputURL
    }
}

extension DebugAnimationToolViewController {

    private func createMutableComposition(
        videoClips: [VideoClip],
        audioURL: URL? = nil,
        size: CGSize,
        duration: TimeInterval
    ) -> (AVMutableComposition, AVMutableAudioMix?)? {
        let until = CMTime(value: Int64(duration * 600), timescale: 600)

        let composition = AVMutableComposition()
        composition.naturalSize = size

        for videoClip in videoClips {
            let avasset   = videoClip.asset
            let timeRange = videoClip.timeRange

            // Inserting video
            guard let mutableVideoTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                return nil
            }

            // Set videoClip trackID
            videoClip.trackID = mutableVideoTrack.trackID
            if let videoTrack = avasset.tracks(withMediaType: .video).first {
                CMTime.loopTime(timeRange: timeRange, until: until) { (at, range) in
                    try? mutableVideoTrack.insertTimeRange(range, of: videoTrack, at: at)
                }
            }

            // Inserting audio if needed
            if !videoClip.isMuted, let audioTrack = avasset.tracks(withMediaType: .audio).first {
                guard let mutableAudioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    return nil
                }
                CMTime.loopTime(timeRange: timeRange, until: until) { (at, range) in
                    try? mutableAudioTrack.insertTimeRange(range, of: audioTrack, at: at)
                }
            }
        }

        var audioMixInputParameters: [AVAudioMixInputParameters] = []

        // Inserting background audio if needed
        if let audioURL = audioURL {
            let audioAsset = AVURLAsset(url: audioURL)
            guard let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
                return nil
            }
            guard let mutableAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                return nil
            }
            let timeRange = CMTimeRange(start: CMTime.zero, duration: audioAssetTrack.timeRange.duration)
            CMTime.loopTime(timeRange: timeRange, until: until) { at, range in
                try? mutableAudioTrack.insertTimeRange(range, of: audioAssetTrack, at: at)
            }

            let inputParameter = AVMutableAudioMixInputParameters(track: mutableAudioTrack)
            let fadeDuration = CMTime(seconds: 1.5, preferredTimescale: 1000)
            let fadeInTimeRange = CMTimeRange(start: .zero, duration: fadeDuration)
            let fadeOutTimeRange = CMTimeRange(start: until - fadeDuration, duration: fadeDuration)
            inputParameter.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: fadeInTimeRange)
            inputParameter.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: fadeOutTimeRange)
            audioMixInputParameters.append(inputParameter)
        }

        let audioMix = { () -> AVMutableAudioMix? in
            if audioMixInputParameters.isEmpty {
                return nil
            }
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixInputParameters
            return audioMix
        }()

        return (composition, audioMix)
    }

    private func createCompositions(
        videoClips: [VideoClip],
        audioURL: URL? = nil,
        size: CGSize,
        transform: CGAffineTransform = .identity,
        duration: TimeInterval
    ) -> AVComponents? {
        // Create composition mixing
        guard let (composition, audioMix) = createMutableComposition(
            videoClips: videoClips, audioURL: audioURL, size: size, duration: duration
        ) else {
            return nil
        }

        // Create video composition
        let timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize    = composition.naturalSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)

        // Set custom compositor and instruction
        videoComposition.customVideoCompositorClass = AnimatedOutputVideoCompositor.self

        let instruction = AnimatedOutputCompositionInstruction(timeRange: timeRange, videoClips: videoClips)
        videoComposition.instructions = [instruction]

        videoComposition.animationTool = { () -> AVVideoCompositionCoreAnimationTool in
            let parentLayer = CALayer()
            let videoLayer  = CALayer()
            videoLayer.frame  = CGRect(x: 0, y: 0, width: 100, height: 100)
            parentLayer.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
            parentLayer.isGeometryFlipped = true
            parentLayer.addSublayer(videoLayer)
            parentLayer.backgroundColor = UIColor.red.cgColor
            return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
        }()

        return (composition: composition, videoComposition: videoComposition, audioMix: audioMix)
    }

}

class TestVC: UIViewController {

    let boxView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(boxView)
        boxView.frame = CGRect(x: 0, y: 0, width: 100, height: 10)
        boxView.backgroundColor = .red
//        CABasicAnimation *scrubbingAnimation = [CABasicAnimation animationWithKeyPath:@"position.x"];
//        scrubbingAnimation.fromValue = [NSNumber numberWithFloat:[self horizontalPositionForTime:kCMTimeZero]];
//        scrubbingAnimation.toValue = [NSNumber numberWithFloat:[self horizontalPositionForTime:duration]];
//        scrubbingAnimation.removedOnCompletion = NO;
//        scrubbingAnimation.beginTime = AVCoreAnimationBeginTimeAtZero;
//        scrubbingAnimation.duration = CMTimeGetSeconds(duration);
//        scrubbingAnimation.fillMode = kCAFillModeBoth;
//        [timeMarkerRedBandLayer addAnimation:scrubbingAnimation forKey:nil];
    }

    func applyAnimation(beginTime: TimeInterval, repeatCount: Float) {
        let moveAnimation = CABasicAnimation(keyPath: "position.x")
        moveAnimation.fromValue = 0
        moveAnimation.toValue = 100
        moveAnimation.autoreverses = true
        moveAnimation.isRemovedOnCompletion = false
        moveAnimation.beginTime = beginTime
        moveAnimation.repeatCount = repeatCount
        boxView.layer.add(moveAnimation, forKey: "ccc")
    }


}

class ExportOp: CBAsyncOperation<Bool> {

    let avComponents: AVComponents
    let url: URL

    let progress = Progress(totalUnitCount: 100)

    private let vc = TestVC()
    private var subscriptions: Set<AnyCancellable> = Set()
    private var exporter: MTVideoExporter?

    weak var superview: UIView?

    init(avComponents: AVComponents, url: URL, superview: UIView?) {
        self.avComponents = avComponents
        self.url = url
        self.superview = superview
    }

    override func workItem() {
        DispatchQueue.main.async { [weak self] in
            self?.export()
        }
    }

    private func export() {
        do {
            let v = vc.view!
            let wrapperView = UIView()
            wrapperView.addSubview(v)
            wrapperView.isHidden = true
            superview?.addSubview(wrapperView)

            vc.applyAnimation(beginTime: AVCoreAnimationBeginTimeAtZero, repeatCount: .infinity)

            let (animationTool, restore) = makeAnimationTool(for: v, size: CGSize(width: 100, height: 200))
            avComponents.videoComposition.animationTool = animationTool

            let exporter = try MTVideoExporter(composition: avComponents.composition, videoComposition: avComponents.videoComposition)
            let session = exporter.export(to: url) { [weak self, wrapperView] error in
                DispatchQueue.main.async {
                    wrapperView.removeFromSuperview()
                    restore()
                }
                guard let self = self else {
                    return
                }
                print("Finished!!!")
                self.result = error == nil
                self.saveVideo(fileURL: self.url)
                self.finish()
            }

            session.progressPublisher().sink { [weak self] progress in
                print(progress)
                self?.progress.completedUnitCount = Int64(progress * 100)
            }.store(in: &subscriptions)

        } catch {
            print(error)
            self.result = false
            self.finish()
        }

    }

    private func saveVideo(fileURL: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
            case .authorized:
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .video, fileURL: fileURL, options: options)
                }) { (success, error) in
                    print(success)
//                    DispatchQueue.main.async {
//                        if success {
//                            let alert = UIAlertController(title: "Video Saved To Camera Roll", message: nil, preferredStyle: .alert)
//                            alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: { _ in
//
//                            }))
//                            self.present(alert, animated: true, completion: nil)
//                        }
//                    }
                }
            default:
                print("PhotoLibrary not authorized")
                break
            }
        }
    }

    private func makeAnimationTool(for targetView: UIView, size: CGSize) -> (AVVideoCompositionCoreAnimationTool, () -> Void) {
        let superLayer = targetView.layer.superlayer
        let parentLayer = CALayer()
        let videoLayer  = CALayer()
        videoLayer.frame  = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        parentLayer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        parentLayer.isGeometryFlipped = true
        parentLayer.addSublayer(videoLayer)

        let originalZIndex = superLayer?.sublayers?.firstIndex(of: targetView.layer)
        let originalGeometry = (targetView.transform, targetView.frame)

        parentLayer.addSublayer(targetView.layer)
        let animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let restoreLayer: () -> Void = {
            if let zIndex = originalZIndex {
                superLayer?.insertSublayer(targetView.layer, at: UInt32(zIndex))
            } else {
                superLayer?.addSublayer(targetView.layer)
            }
            (targetView.transform, targetView.frame) = originalGeometry
        }
        return (animationTool, restoreLayer)
    }

}
