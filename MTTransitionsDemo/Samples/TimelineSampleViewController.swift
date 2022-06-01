//
//  TimelineSampleViewController.swift
//  MTTransitionsDemo
//
//  Created by Jim Wang on 2022/5/31.
//  Copyright © 2022 xu.shuifeng. All rights reserved.
//

import UIKit
import AVFoundation
import MTTransitions
import Photos

class TimelineSampleViewController: UIViewController {

    private var videoView: UIView!
    private var nameLabel: UILabel!
    private var pickButton: UIButton!
    private var player: AVPlayer!
    private var playerLayer: AVPlayerLayer!

    private var composition: MTTimelineComposition?
    private var timeline: Timeline?

    private let videoTransition = MTVideoTransition()
    private var clips: [AVAsset] = []

    private var exportButton: UIBarButtonItem!

    private var result: MTVideoTransitionResult?
    private var exporter: MTVideoExporter?

    private var effect = MTTransition.Effect.circleOpen

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        view.backgroundColor = .white

        setupVideoPlaybacks()
        setupSubviews()
        setupNavigationBar()
        makeComposition()
//        makeTransition()

        setupDebugView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        playerLayer.frame = videoView.bounds
    }

    private let debugView = APLCompositionDebugView()

    private func setupDebugView() {
        debugView.player = player
        debugView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(debugView)
        NSLayoutConstraint.activate([
            debugView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            debugView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            debugView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -80),
            debugView.heightAnchor.constraint(equalToConstant: 300)
        ])
    }

    private func setupSubviews() {
        videoView = UIView()
        view.addSubview(videoView)
        videoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            videoView.widthAnchor.constraint(equalTo: self.view.widthAnchor),
            videoView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: -80),
            videoView.heightAnchor.constraint(equalTo: self.view.widthAnchor, multiplier: 720.0/1280.0)
        ])

        let url = Bundle.main.url(forResource: "clip1", withExtension: "mp4")!
        player = AVPlayer(url: url)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        videoView.layer.addSublayer(playerLayer)
        videoView.backgroundColor = UIColor.green

        nameLabel = UILabel()
        nameLabel.text = effect.description
        nameLabel.textAlignment = .center
        view.addSubview(nameLabel)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            nameLabel.topAnchor.constraint(equalTo: videoView.bottomAnchor, constant: 15)
        ])

        pickButton = UIButton(type: .system)
        pickButton.setTitle("Pick A Transition", for: .normal)
        view.addSubview(pickButton)

        pickButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pickButton.topAnchor.constraint(equalTo: self.nameLabel.bottomAnchor, constant: 30),
            pickButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
        ])

        pickButton.addTarget(self, action: #selector(handlePickButtonClicked), for: .touchUpInside)

        setupSizeButtons()
    }

    private func setupVideoPlaybacks() {
        guard let clip1 = loadVideoAsset(named: "clip1"),
              let clip2 = loadVideoAsset(named: "clip2") else {
                  return
              }
        clips = [clip1, clip2]
    }

    private func setupNavigationBar() {
        exportButton = UIBarButtonItem(title: "Export", style: .plain, target: self, action: #selector(handleExportButtonClicked))
        exportButton.isEnabled = false

        navigationItem.rightBarButtonItem = exportButton
    }

    private func setupSizeButtons() {
        let hStack: UIStackView = {
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.spacing = 8
            stack.alignment = .fill
            stack.distribution = .equalSpacing
            return stack
        }()

        let portrait = UIButton(type: .custom)
        portrait.setTitle("9:16", for: .normal)
        portrait.tag = 0
        portrait.addTarget(self, action: #selector(handleChangeSize(_:)), for: .touchUpInside)

        let square = UIButton(type: .custom)
        square.setTitle("1:1", for: .normal)
        square.tag = 1
        square.addTarget(self, action: #selector(handleChangeSize(_:)), for: .touchUpInside)

        let landscape = UIButton(type: .custom)
        landscape.setTitle("16:9", for: .normal)
        landscape.tag = 2
        landscape.addTarget(self, action: #selector(handleChangeSize(_:)), for: .touchUpInside)

        [portrait, square, landscape].forEach { button in
            button.backgroundColor = UIColor.gray
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 60)
            ])
            hStack.addArrangedSubview(button)
        }

        view.addSubview(hStack)
        hStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hStack.topAnchor.constraint(equalTo: pickButton.bottomAnchor, constant: 30),
            hStack.leadingAnchor.constraint(equalTo: hStack.arrangedSubviews.first!.leadingAnchor),
            hStack.trailingAnchor.constraint(equalTo: hStack.arrangedSubviews.last!.trailingAnchor),
            hStack.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    private func makeComposition(renderSize: CGSize = CGSize(width: 720, height: 720)) {
        let timeline = Timeline()
        timeline.renderSize = renderSize
        let resource1 = AVAssetResource(asset: loadVideoAsset(named: "clip1")!, selectedTimeRange: nil)
        let resource2 = AVAssetResource(asset: loadVideoAsset(named: "clip2")!, selectedTimeRange: nil)
        let resource3 = AVAssetResource(asset: loadVideoAsset(named: "clip3")!, selectedTimeRange: nil)
        timeline.clips = [
            Clip(resource: resource1),
            Clip(resource: resource2),
            Clip(resource: resource3)
        ]
        timeline.transitions = [
            MTTransition.Effect.angular,
            MTTransition.Effect.angular
        ]

        let composition = MTTimelineComposition(timeline: timeline)
        do {
            let playerItem = try composition.buildPlayerItem()
            self.player.seek(to: .zero)
            self.player.replaceCurrentItem(with: playerItem)
            self.player.play()
            self.registerNotifications()

            self.debugView.synchronize(
                to: playerItem.asset as? AVComposition,
                videoComposition: playerItem.videoComposition,
                audioMix: playerItem.audioMix
            )
        } catch {
            debugPrint(error)
        }
        self.composition = composition
    }

    private func makeTransition(renderSize: CGSize? = CGSize(width: 720, height: 720)) {
        videoTransition.renderSize = renderSize

        let duration = CMTimeMakeWithSeconds(2.0, preferredTimescale: 1000)
        try? videoTransition.merge(clips, effect: effect, transitionDuration: duration) { [weak self] result in
            guard let self = self else { return }
            let playerItem = AVPlayerItem(asset: result.composition)
            playerItem.videoComposition = result.videoComposition

            self.player.seek(to: .zero)
            self.player.replaceCurrentItem(with: playerItem)
            self.player.play()

            self.registerNotifications()

            self.result = result
            self.exportButton.isEnabled = true
        }
    }

    private func registerNotifications() {
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.handlePlayToEndTime),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: player.currentItem)
    }

    private func export(_ result: MTVideoTransitionResult) {
        exporter = try? MTVideoExporter(transitionResult: result)
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory().appending("exported.mp4"))
        exporter?.export(to: fileURL, completion: { error in
            if let error = error {
                print("Export error:\(error)")
            } else {
                self.saveVideo(fileURL: fileURL)
            }
        })
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
                    DispatchQueue.main.async {
                        if success {
                            let alert = UIAlertController(title: "Video Saved To Camera Roll", message: nil, preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: { _ in

                            }))
                            self.present(alert, animated: true, completion: nil)
                        }
                    }
                }
            default:
                print("PhotoLibrary not authorized")
                break
            }
        }
    }
}

// MARK: - Events
extension TimelineSampleViewController {

    @objc private func handleExportButtonClicked() {
        guard let result = result else {
            return
        }
        self.export(result)
    }

    @objc private func handlePlayToEndTime() {
        player.seek(to: .zero)
        player.play()
    }

    @objc private func handlePickButtonClicked() {
        let pickerVC = TransitionsPickerViewController()
        pickerVC.selectionUpdated = { [weak self] effect in
            guard let self = self else { return }
            self.effect = effect
            self.nameLabel.text = effect.description
            self.result = nil
            self.exportButton.isEnabled = false
            self.makeTransition()
        }
        let nav = UINavigationController(rootViewController: pickerVC)
        present(nav, animated: true, completion: nil)
    }

    @objc private func handleChangeSize(_ sender: UIButton) {
        let newRenderSize = { () -> CGSize in
            let dimension: Int = 720
            switch sender.tag {
            case 0: // Portrait
                return CGSize(width: dimension, height:  Int(CGFloat(dimension) * 16.0 / 9.0))
            case 1: // Square
                return CGSize(width: dimension, height: dimension)
            case 2: // Landscape
                return CGSize(width: Int(CGFloat(dimension) * 16.0 / 9.0), height: dimension)
            default:
                assertionFailure("unexpected value")
                return .zero
            }
        }()
        guard videoTransition.renderSize != newRenderSize else {
            return
        }
        makeTransition(renderSize: newRenderSize)
    }
}

// MARK: - Helper
extension TimelineSampleViewController {

    private func loadVideoAsset(named: String, withExtension ext: String = "mp4") -> AVURLAsset? {
        guard let url = Bundle.main.url(forResource: named, withExtension: ext) else {
            return nil
        }
        return AVURLAsset(url: url)
    }
}
