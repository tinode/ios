//
//  CallViewController.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//


import AVFoundation
import Foundation
import TinodeSDK
import UIKit
import WebRTC

@objc
protocol CameraCaptureDelegate: AnyObject {
    func captureVideoOutput(sampleBuffer: CMSampleBuffer)
}

class CameraManager: NSObject {
    var videoCaptureDevice: AVCaptureDevice?
    let captureSession = AVCaptureSession()
    let videoDataOutput = AVCaptureVideoDataOutput()
    let audioDataOutput = AVCaptureAudioDataOutput()
    let dataOutputQueue = DispatchQueue(label: "VideoDataQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    weak var delegate: CameraCaptureDelegate?

    var isCapturing = false

    func setupCamera() {
        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else { return }

        self.videoCaptureDevice = videoCaptureDevice

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }

        // Cap video camera resolution (best effort).
        // Otherwise, remote video stream may freeze
        // https://stackoverflow.com/questions/55841076/webrtc-remote-video-freeze-after-few-seconds
        if captureSession.canSetSessionPreset(.iFrame1280x720) {
            captureSession.sessionPreset = .iFrame1280x720
        } else if captureSession.canSetSessionPreset(.iFrame960x540) {
            captureSession.sessionPreset = .iFrame960x540
        } else if captureSession.canSetSessionPreset(.vga640x480) {
            captureSession.sessionPreset = .vga640x480
        } else {
            Cache.log.error("CallVC - Could not scale down video resolution")
        }

        // Add a video data output
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
            videoDataOutput.connection(with: .video)?.videoOrientation = .portrait
            videoDataOutput.connection(with: .video)?.automaticallyAdjustsVideoMirroring = false
            videoDataOutput.connection(with: .video)?.isVideoMirrored = true
        } else {
            Cache.log.error("CallVC - Could not add video data output to the session")
            captureSession.commitConfiguration()
        }
    }

    func startCapture(completion: (() -> Void)? = nil) {
        Cache.log.info("CallVC - CameraManager: start capture")

        guard !isCapturing else { return }
        isCapturing = true

        #if arch(arm64)
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
            completion?()
        }
        #else
        completion?()
        #endif
    }
    func stopCapture(completion: (() -> Void)? = nil) {
        Cache.log.info("CallVC - CameraManager: end capture")
        guard isCapturing else { return }
        isCapturing = false

        #if arch(arm64)
        DispatchQueue.global(qos: .background).async {
            self.captureSession.stopRunning()
            completion?()
        }
        #else
        completion?()
        #endif
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if connection == videoDataOutput.connection(with: .video) {
            delegate?.captureVideoOutput(sampleBuffer: sampleBuffer)
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    }
}

/// WebRTCClient
/// Methods for dispatching local events to the peer.
protocol WebRTCClientDelegate: AnyObject {
    func handleRemoteStream(_ client: WebRTCClient, receivedStream stream: RTCMediaStream)
    func sendOffer(withDescription sdp: RTCSessionDescription)
    func sendAnswer(withDescription sdp: RTCSessionDescription)
    func sendIceCandidate(_ candidate: RTCIceCandidate)
    func closeCall()
    func canSendOffer() -> Bool
    func markConnectionSetupComplete()
    func enableMediaControls()
    // Toggle remote video.
    func toggleRemoteVideo(remoteLive: Bool)
    // Returns true is the call is originated as audio only.
    var isAudioOnlyCall: Bool { get }
}

/// TinodeVideoCallDelegate
/// Methods for handling remote messages received from the peer.
protocol TinodeVideoCallDelegate: AnyObject {
    func eventMatchesCallInProgress(info: MsgServerInfo) -> Bool
    func handleAcceptedMsg()
    func handleOfferMsg(with payload: JSONValue?)
    func handleAnswerMsg(with payload: JSONValue?)
    func handleIceCandidateMsg(with payload: JSONValue?)
    func handleRemoteHangup()
    func handleRinging()
}

class WebRTCClient: NSObject {
    static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    private static let kVideoCallMediaConstraints = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                                    kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue]
    private static let kAudioOnlyMediaConstraints = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue]
    // Video muted/unmuted events.
    public static let kVideoEventMuted = "video:muted"
    public static let kVideoEventUnmuted = "video:unmuted"

    private var localPeer: RTCPeerConnection?
    private var localDataChannel: RTCDataChannel?
    private var localVideoSource: RTCVideoSource?
    private var localVideoTrack: RTCVideoTrack?
    private var videoCapturer: RTCVideoCapturer?
    private var remoteVideoTrack: RTCVideoTrack?

    private var localAudioTrack: RTCAudioTrack?

    private var remoteIceCandidatesCacheQueue = DispatchQueue(label: "co.tinode.webrtc.ice-candidates-queue")
    private var remoteIceCandidatesCache: [RTCIceCandidate] = []

    weak var delegate: WebRTCClientDelegate?

    func setup() {
        createMediaSenders()
    }

    func toggleAudio() -> Bool {
        guard let track = self.localAudioTrack else { return false }
        track.isEnabled = !track.isEnabled
        return track.isEnabled
    }

    func toggleVideo() -> Bool {
        guard let track = self.localVideoTrack else { return false }
        track.isEnabled = !track.isEnabled
        return track.isEnabled
    }

    // Adds remote ICE candidate to either the peer connection when it exists
    // or the cache when the hasn't been created yet.
    func handleRemoteIceCandidate(_ candidate: RTCIceCandidate, saveInCache: Bool) {
        if !saveInCache {
            self.localPeer?.add(candidate) { err in
                if let err = err {
                    Cache.log.error("WebRTCClient: could not add ICE candidate: %@", err.localizedDescription)
                    self.delegate?.closeCall()
                }
            }
        } else {
            self.remoteIceCandidatesCacheQueue.sync {
                self.remoteIceCandidatesCache.append(candidate)
            }
        }
    }

    // Adds all locally cached remote ICE candidates to the peer connection.
    func drainIceCandidatesCache() {
        Cache.log.info("Draining iceCandidateCache: %d items", self.remoteIceCandidatesCache.count)
        var success = true
        self.remoteIceCandidatesCacheQueue.sync {
            self.remoteIceCandidatesCache.forEach { candidate in
                self.localPeer?.add(candidate) { err in
                    if let err = err {
                        Cache.log.error("WebRTCClient.drainIceCandidatesCache - could not add ICE candidate: %@", err.localizedDescription)
                        success = false
                    }
                }
            }
            self.remoteIceCandidatesCache.removeAll()
        }
        if !success {
            self.delegate?.closeCall()
        }
    }

    func createPeerConnection(withDataChannel dataChannel: Bool) -> Bool {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let config = generateRTCConfig() else {
            Cache.log.info("WebRTCClient - missing configuration. Quitting.")
            return false
        }

        localPeer = WebRTCClient.factory.peerConnection(with: config, constraints: constraints, delegate: self)
        guard localPeer != nil else {
            Cache.log.error("WebRtCClient - failed to create peer connection. Quitting.")
            return false
        }

        if dataChannel {
            let chanConfig = RTCDataChannelConfiguration()
            chanConfig.isOrdered = true
            self.localDataChannel = localPeer!.dataChannel(forLabel: "events", configuration: chanConfig)
            self.localDataChannel?.delegate = self
        }

        let stream = WebRTCClient.factory.mediaStream(withStreamId: "ARDAMS")
        stream.addAudioTrack(self.localAudioTrack!)
        stream.addVideoTrack(self.localVideoTrack!)
        localPeer!.add(stream)
        return true
    }

    func offer(_ peerConnection: RTCPeerConnection) {
        Cache.log.info("WebRTCClient - creating offer")
        let constraints = self.delegate?.isAudioOnlyCall ?? false ? WebRTCClient.kAudioOnlyMediaConstraints : WebRTCClient.kVideoCallMediaConstraints
        peerConnection.offer(for: RTCMediaConstraints(mandatoryConstraints: constraints, optionalConstraints: nil), completionHandler: { [weak self](sdp, error) in
            guard let self = self else { return }

            guard let sdp = sdp else {
                // Missing SDP.
                if let error = error {
                    Cache.log.error("WebRTCClient - failed to make offer SDP %@", error.localizedDescription)
                }
                self.delegate?.closeCall()
                return
            }

            peerConnection.setLocalDescription(sdp, completionHandler: { (error) in
                if let error = error {
                    Cache.log.error("WebRTCClient - failed to set local SDP (offer) %@", error.localizedDescription)
                    self.delegate?.closeCall()
                    return
                }
                self.delegate?.sendOffer(withDescription: sdp)
            })
        })
    }

    func answer(_ peerConnection: RTCPeerConnection) {
        Cache.log.info("WebRTCClient - creating answer")
        let constraints = self.delegate?.isAudioOnlyCall ?? false ? WebRTCClient.kAudioOnlyMediaConstraints : WebRTCClient.kVideoCallMediaConstraints
        peerConnection.answer(
            for: RTCMediaConstraints(mandatoryConstraints: constraints, optionalConstraints: nil),
            completionHandler: { [weak self](sdp, error) in
                guard let self = self, let sdp = sdp else {
                    if let error = error {
                        Cache.log.error("WebRTCClient - failed to make answer SDP %@", error.localizedDescription)
                    }
                    self?.delegate?.closeCall()
                    return
                }

                peerConnection.setLocalDescription(sdp, completionHandler: { [weak self](error) in
                    if let error = error {
                        Cache.log.error("WebRTCClient - failed to set local SDP (answer) %@", error.localizedDescription)
                        self?.delegate?.closeCall()
                        return
                    }
                    self?.delegate?.sendAnswer(withDescription: sdp)
                    self?.delegate?.markConnectionSetupComplete()
                })
            })
    }

    func sendOverDataChannel(event: String) {
        self.localDataChannel?.sendData(RTCDataBuffer(data: Data(event.utf8), isBinary: false))
    }

    func disconnect() {
        localPeer?.close()
        localPeer = nil

        // Clean up audio.
        localAudioTrack = nil

        // ... and video.
        localVideoSource = nil
        localVideoTrack = nil
        videoCapturer = nil
        remoteVideoTrack = nil
    }
}

extension WebRTCClient: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("channel state \(dataChannel.readyState)")
        switch dataChannel.readyState {
        case .open:
            if !(self.delegate?.isAudioOnlyCall ?? true) {
                sendOverDataChannel(event: WebRTCClient.kVideoEventUnmuted)
            }
        default:
            break
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let event = String(decoding: buffer.data, as: UTF8.self)
        switch event {
        case WebRTCClient.kVideoEventMuted:
            self.delegate?.toggleRemoteVideo(remoteLive: false)
        case WebRTCClient.kVideoEventUnmuted:
            self.delegate?.toggleRemoteVideo(remoteLive: true)
        default:
            break
        }
    }
}

// MARK: Preparation/setup.
extension WebRTCClient {
    // TODO: ICE/WebRTC config should be obtained from the server.
    private func generateRTCConfig() -> RTCConfiguration? {
        let tinode = Cache.tinode
        guard let iceConfig = tinode.getServerParam(for: "iceServers")?.asArray() else {
            Cache.log.error("WebRTCClient.generateRTCConfig: Missing/invalid iceServers server parameter")
            return nil
        }

        let config = RTCConfiguration()
        // TODO: planB for now. Need to migrate to unified in the future.
        config.sdpSemantics = .planB
        // TCP candidates are only useful when connecting to a server that supports
        // ICE-TCP.
        config.tcpCandidatePolicy = .disabled
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.continualGatheringPolicy = .gatherContinually
        // Use ECDSA encryption.
        config.keyType = .ECDSA

        for v in iceConfig {
            guard let vals = v.asDict() else {
                return nil
            }
            if let urls = vals["urls"]?.asArray() {
                let iceStrings = urls.compactMap { $0.asString() }
                var ice: RTCIceServer
                if let username = vals["username"]?.asString() {
                    let credential = vals["credential"]?.asString()
                    ice = RTCIceServer(urlStrings: iceStrings, username: username, credential: credential)
                } else {
                    ice = RTCIceServer(urlStrings: iceStrings)
                }
                config.iceServers.append(ice)
            } else {
                Cache.log.info("Invalid ICE server config: no URLs")
            }
        }
        return config
    }

    private func createMediaSenders() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: [:], optionalConstraints: nil)
        let audioSource = WebRTCClient.factory.audioSource(with: constraints)
        let audioTrack = WebRTCClient.factory.audioTrack(with: audioSource, trackId: "ARDAMSa0")
        localAudioTrack = audioTrack

        let videoSource = WebRTCClient.factory.videoSource()
        localVideoSource = videoSource
        let videoTrack = WebRTCClient.factory.videoTrack(with: videoSource, trackId: "ARDAMSv0")
        localVideoTrack = videoTrack
        videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
    }
}

// MARK: UI Handling
extension WebRTCClient {
    func setupLocalRenderer(_ renderer: RTCVideoRenderer) {
        guard let localVideoTrack = localVideoTrack else { return }
        localVideoTrack.add(renderer)
    }

    func setupRemoteRenderer(_ renderer: RTCVideoRenderer, withTrack track: RTCVideoTrack?) {
        guard let track = track else { return }
        self.remoteVideoTrack = track
        track.add(renderer)
    }

    func didCaptureLocalFrame(_ videoFrame: RTCVideoFrame) {
        guard let videoSource = localVideoSource,
            let videoCapturer = videoCapturer else { return }
        videoSource.capturer(videoCapturer, didCapture: videoFrame)
    }
}

// MARK: Message Handling
extension WebRTCClient {
    // Processes remote offer SDP.
    func handleRemoteOfferDescription(_ desc: RTCSessionDescription) {
        guard let peerConnection = localPeer else { return }
        peerConnection.setRemoteDescription(desc, completionHandler: { [weak self](error) in
            guard let self = self else { return }
            if let error = error {
                Cache.log.error("WebRTCClient.handleRemoteOfferDescription failure: %@", error.localizedDescription)
                self.delegate?.closeCall()
                return
            }
            self.answer(peerConnection)
        })
    }

    // Processes remote answer SDP.
    func handleRemoteAnswerDescription(_ desc: RTCSessionDescription) {
        self.localPeer?.setRemoteDescription(desc, completionHandler: { (error) in
            if let e = error {
                Cache.log.error("WebRTCClient.handleRemoteAnswerDescription failure: %@", e.localizedDescription)
                self.delegate?.closeCall()
                return
            }
            self.delegate?.markConnectionSetupComplete()
        })
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        switch stateChanged {
        case .closed:
            self.delegate?.closeCall()
        case .stable:
            self.delegate?.enableMediaControls()
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Cache.log.info("WebRTCClient: Received remote stream %@", stream)
        self.delegate?.handleRemoteStream(self, receivedStream: stream)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Cache.log.info("WebRTCClient: Removed media stream %@", stream)
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        guard (self.delegate?.canSendOffer() ?? false) && !peerConnection.senders.isEmpty else {
            return
        }
        Cache.log.info("WebRTCClient: negotiating connection")
        self.offer(peerConnection)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .closed:
            fallthrough
        case .failed:
            self.delegate?.closeCall()
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Cache.log.info("WebRTCClient: ice rtc gathering state - %d", newState.rawValue)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Cache.log.info("WebRTCClient: new local ice candidate %@", candidate)
        self.delegate?.sendIceCandidate(candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        Cache.log.info("WebRTCClient: removed ice candidates %@", candidates)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        Cache.log.info("WebRTCClient: opened data channel %@", dataChannel)
        self.localDataChannel = dataChannel
        self.localDataChannel!.delegate = self
    }
}

extension RTCSessionDescription {
    func serialize() -> JSONValue? {
        let typeStr = RTCSessionDescription.string(for: self.type)
        let dict = ["type": JSONValue.string(typeStr),
                    "sdp": JSONValue.string(self.sdp)]
        return .dict(dict)
    }

    static func deserialize(from dict: [String: JSONValue]) -> RTCSessionDescription? {
        guard let type = dict["type"]?.asString(), let sdp = dict["sdp"]?.asString() else {
            return nil
        }
        return RTCSessionDescription(type: RTCSessionDescription.type(for: type), sdp: sdp)
    }
}

extension RTCIceCandidate {
    func serialize() -> JSONValue? {
        var dict = ["type": JSONValue.string("candidate"),
                    "sdpMLineIndex": JSONValue.int(Int(self.sdpMLineIndex)),
                    "candidate": JSONValue.string(self.sdp)
        ]
        if let sdpMid = self.sdpMid {
            dict["sdpMid"] = JSONValue.string(sdpMid)
        }
        return .dict(dict)
    }

    static func deserialize(from dict: [String: JSONValue]) -> RTCIceCandidate? {
        guard let sdp = dict["candidate"]?.asString() else {
            return nil
        }
        let idx = dict["sdpMLineIndex"]?.asInt()
        let sdpMid = dict["sdpMid"]?.asString()
        return RTCIceCandidate(sdp: sdp, sdpMLineIndex: Int32(idx ?? 0), sdpMid: sdpMid)
    }
}

/// CallViewController
class CallViewController: UIViewController {
    private enum Constants {
        static let kToggleCameraIcon = "vc"
        static let kToggleMicIcon = "mic"
        static let kDialingAnimationDuration: Double = 1.5
        static let kDialingAnimationColor = UIColor(red: 33.0/255.0, green: 150.0/255.0, blue: 243.0/255.0, alpha: 1).cgColor
    }

    enum CallDirection {
        case none
        case outgoing
        case incoming
    }

    @IBOutlet weak var remoteView: UIView!
    @IBOutlet weak var localView: UIView!

    @IBOutlet weak var localViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var localViewWidthConstraint: NSLayoutConstraint!

    @IBOutlet weak var speakerToggleButton: UIButton!
    @IBOutlet weak var micToggleButton: UIButton!
    @IBOutlet weak var videoToggleButton: UIButton!
    @IBOutlet weak var hangUpButton: UIButton!

    @IBOutlet weak var peerNameLabel: PaddedLabel!
    @IBOutlet weak var peerAvatarImageView: RoundImageView!
    @IBOutlet weak var peerNameRemoteVideoLabel: PaddedLabel!

    @IBOutlet weak var dialingAnimationContainer: UIView!

    private static func actionButtonIcon(iconName: String, on: Bool) -> UIImage? {
        let name = "\(iconName)\(on ? "" : ".slash").fill"
        return UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
    }

    weak var topic: DefaultComTopic?
    let cameraManager = CameraManager()
    let webRTCClient = WebRTCClient()
    // Peer messasges listener.
    var listener: InfoListener!

    var remoteRenderer: RTCVideoRenderer?

    var callDirection: CallDirection = .none
    var callSeqId: Int = -1
    var isAudioOnlyCall: Bool = false
    // If true, the client has received a remote SDP from the peer and has sent a local SDP to the peer.
    var callInitialSetupComplete = false
    // Audio output destination (.none = default).
    var audioOutput: AVAudioSession.PortOverride = .none
    // Audio route change notification observer.
    var routeChangeObserver: NSObjectProtocol?
    // For playing sound effects.
    var audioPlayer: AVAudioPlayer?

    class InfoListener: TinodeEventListener {
        private weak var delegate: TinodeVideoCallDelegate?
        init(delegateEventsTo callDelegate: TinodeVideoCallDelegate) {
            self.delegate = callDelegate
        }

        func onInfoMessage(info: MsgServerInfo?) {
            guard let info = info, self.delegate?.eventMatchesCallInProgress(info: info) ?? false else { return }
            switch info.event {
            case "accept":
                DispatchQueue.main.async { self.delegate?.handleAcceptedMsg() }
            case "offer":
                DispatchQueue.main.async { self.delegate?.handleOfferMsg(with: info.payload) }
            case "answer":
                DispatchQueue.main.async { self.delegate?.handleAnswerMsg(with: info.payload) }
            case "ice-candidate":
                DispatchQueue.main.async { self.delegate?.handleIceCandidateMsg(with: info.payload) }
            case "hang-up":
                DispatchQueue.main.async { self.delegate?.handleRemoteHangup() }
            case "ringing":
                DispatchQueue.main.async { self.delegate?.handleRinging() }
            default:
                print(info)
            }
        }
    }

    override func viewDidLoad() {
        self.videoToggleButton.addBlurEffect()
        self.micToggleButton.addBlurEffect()
        self.speakerToggleButton.addBlurEffect()

        if self.isAudioOnlyCall {
            self.audioOutput = .none
            self.videoToggleButton.setImage(UIImage(named: "vc.slash.fill", in: nil, with: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)), for: .normal)
            self.speakerToggleButton.setImage(UIImage(systemName: "speaker.wave.1.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)), for: .normal)
        } else {
            self.audioOutput = .speaker
        }
        self.listener = InfoListener(delegateEventsTo: self)

        if let topic = topic {
            peerNameLabel.text = topic.pub?.fn
            peerNameLabel.sizeToFit()
            peerNameRemoteVideoLabel.text = peerNameLabel.text
            peerNameRemoteVideoLabel.sizeToFit()
            peerAvatarImageView.set(pub: topic.pub, id: topic.name, deleted: false)
        }
    }

    @IBAction func didToggleSpeaker(_ sender: Any) {
        var newIconName: String
        var newOutput: AVAudioSession.PortOverride
        switch self.audioOutput {
        case .none:
            newIconName = "speaker.wave.3.fill"
            newOutput = .speaker
        case .speaker:
            newIconName = "speaker.wave.1.fill"
            newOutput = .none
        default:
            Cache.log.error("unknown AVAudioSession.PortOverride value: %d", self.audioOutput.rawValue)
            return
        }
        let newimg = UIImage(systemName: newIconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        Cache.log.info("User requested overridde audio output port to %d", newOutput.rawValue)
        CallManager.audioSessionChange { session in
            try session.overrideOutputAudioPort(newOutput)
            self.speakerToggleButton.setImage(newimg, for: .normal)
            self.audioOutput = newOutput
        }
    }

    @IBAction func didToggleMic(_ sender: Any) {
        let img = UIImage(systemName: self.webRTCClient.toggleAudio() ? "mic.fill" : "mic.slash.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        self.micToggleButton.setImage(img, for: .normal)
    }

    @IBAction func didToggleCamera(_ sender: Any) {
        let newimg = UIImage(named: cameraManager.isCapturing ? "vc.slash.fill" : "vc.fill", in: nil, with: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))

        videoToggleButton.isEnabled = false
        if cameraManager.isCapturing {
            cameraManager.stopCapture {
                DispatchQueue.main.async {
                    self.localView.isHidden = true
                    self.webRTCClient.sendOverDataChannel(event: WebRTCClient.kVideoEventMuted)
                    self.videoToggleButton.isEnabled = true
                    self.videoToggleButton.setImage(newimg, for: .normal)
                    self.videoToggleButton.imageEdgeInsets = UIEdgeInsets(top: 14, left: 14, bottom: 19, right: 15)
                }
            }
        } else {
            cameraManager.startCapture {
                DispatchQueue.main.async {
                    self.localView.isHidden = false
                    self.webRTCClient.sendOverDataChannel(event: WebRTCClient.kVideoEventUnmuted)
                    self.videoToggleButton.isEnabled = true
                    self.videoToggleButton.setImage(newimg, for: .normal)
                    self.videoToggleButton.imageEdgeInsets = UIEdgeInsets(top: 14, left: 15, bottom: 20, right: 15)
                }
            }
        }
    }

    @IBAction func didTapHangUp(_ sender: Any) {
        self.handleCallClose()
    }

    private func setupCaptureSessionAndStartCall() {
        cameraManager.setupCamera()
        if (!self.isAudioOnlyCall) {
            cameraManager.startCapture()
        }
        setupViews()

        routeChangeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil, using: handleRouteChange)

        webRTCClient.delegate = self
        cameraManager.delegate = self
        Cache.tinode.addListener(self.listener)
        // Prevent screen from dimming/going to sleep.
        UIApplication.shared.isIdleTimerDisabled = true

        if let topic = self.topic {
            if !topic.attached {
                topic.subscribe().then(
                    onSuccess: { [weak self] msg in
                        if let ctrl = msg?.ctrl, ctrl.code < 300 {
                            self?.handleCallInvite()
                        } else {
                            self?.handleCallClose()
                        }
                        return nil
                    },
                    onFailure: { [weak self] err in
                        self?.handleCallClose()
                        return nil
                    })
            } else {
                self.handleCallInvite()
            }
        } else {
            self.handleCallClose()
        }
    }

    private func checkMicPermissions(completion: @escaping ((Bool) -> Void)) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                completion(true)  // success
            } else {
                completion(false)  // failure
            }
        }
    }

    private func checkCameraPermissions(completion: @escaping ((Bool) -> Void)) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)  // success
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    completion(true)  // success
                } else {
                    completion(false)  // failure
                }
            }
        case .denied, .restricted:
            fallthrough
        @unknown default:
            completion(false)  // failure
        }
    }

    private enum PermissionsCheckResult {
        case ok
        case micDenied
        case cameraDenied
    }

    private func permissionsCheck(completion: @escaping (PermissionsCheckResult) -> Void) {
        self.checkMicPermissions { success in
            guard success else {
                completion(.micDenied)
                return
            }
            if self.isAudioOnlyCall {
                completion(.ok)
                return
            }
            self.checkCameraPermissions { success in
                completion(success ? .ok : .cameraDenied)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        self.permissionsCheck { result in
            switch result {
            case .ok:
                DispatchQueue.main.async { self.setupCaptureSessionAndStartCall() }
            case .micDenied:
                Cache.log.error("No permission to access microphone")
                DispatchQueue.main.async {
                    UiUtils.showToast(message: NSLocalizedString("No permission to access microphone", comment: "Error message when call cannot be started due to missing microphone permission"))
                    self.handleCallClose()
                }
            case .cameraDenied:
                Cache.log.error("No permission to access camera")
                DispatchQueue.main.async {
                    UiUtils.showToast(message: NSLocalizedString("No permission to access camera", comment: "Error message when call cannot be started due to missing camera permission"))
                    self.handleCallClose()
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        self.handleCallClose()
        Cache.tinode.removeListener(self.listener)
    }

    override func viewDidDisappear(_ animated: Bool) {
        self.stopMedia()
    }

    @objc func handleRouteChange(notification: Notification) {
        guard let info = notification.userInfo,
            let value = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: value) else { return }

        switch reason {
        case .categoryChange:
            Cache.log.info("Audio route change: .categoryChange, restoring audio output to %d", self.audioOutput.rawValue)
            CallManager.audioSessionChange { session in
                try session.overrideOutputAudioPort(self.audioOutput)
            }
        case .oldDeviceUnavailable:
            Cache.log.info("Audio route change: .oldDeviceUnavailable, restoring audio output to %d", self.audioOutput.rawValue)
            CallManager.audioSessionChange { session in
                try session.overrideOutputAudioPort(self.audioOutput)
            }
        default:
            Cache.log.debug("CallVC - audio route change: other - %@, reason: %d", value.description, reason.rawValue)
        }
    }

    func setupViews() {
        #if arch(arm64)
            // Using metal (arm64 only)
            let localRenderer = RTCMTLVideoView(frame: self.localView.frame)
            let remoteRenderer = RTCMTLVideoView(frame: self.remoteView.frame)
            localRenderer.videoContentMode = .scaleAspectFit
            remoteRenderer.videoContentMode = .scaleAspectFill
        #else
            // Using OpenGLES for the rest
            let localRenderer = RTCEAGLVideoView(frame: self.localView.frame)
            let remoteRenderer = RTCEAGLVideoView(frame: self.remoteView.frame)
        #endif

        webRTCClient.setup()
        webRTCClient.setupLocalRenderer(localRenderer)

        self.embedView(localRenderer, into: localView)
        self.embedView(remoteRenderer, into: remoteView)

        self.remoteRenderer = remoteRenderer
        if self.isAudioOnlyCall {
            remoteView.isHidden = true
            peerNameRemoteVideoLabel.isHidden = true
            localView.isHidden = true
        }
    }

    func stopMedia() {
        // Allow screen dimming/going to sleep.
        UIApplication.shared.isIdleTimerDisabled = false

        self.webRTCClient.disconnect()
        cameraManager.stopCapture()
        if let observer = self.routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func handleCallClose() {
        playSoundEffect(nil)

        Cache.callManager.completeCallInProgress(reportToSystem: true, reportToPeer: false)
        if self.callSeqId > 0 {
            self.topic?.videoCall(event: "hang-up", seq: self.callSeqId)
        }
        self.callSeqId = -1
        DispatchQueue.main.async {
            // Dismiss video call VC.
            self.navigationController?.popViewController(animated: true)
        }
    }

    func handleCallInvite() {
        switch self.callDirection {
        case .outgoing:
            guard Cache.callManager.registerOutgoingCall(onTopic: self.topic!.name, isAudioOnly: self.isAudioOnlyCall) else {
                self.handleCallClose()
                return
            }
            playSoundEffect("dialing")
            // Send out a call invitation to the peer.
            self.topic?.publish(content: Drafty.videoCall(),
                                withExtraHeaders:["webrtc": .string(MsgServerData.WebRTC.kStarted.rawValue),
                                                  "aonly": .bool(self.isAudioOnlyCall)]).then(onSuccess: { msg in
                guard let ctrl = msg?.ctrl else { return nil }
                if ctrl.code < 300, let seq = ctrl.getIntParam(for: "seq"), seq > 0 {
                    // All good. Register the call.
                    self.callSeqId = seq
                    Cache.callManager.updateOutgoingCall(withNewSeqId: seq)
                    return nil
                }
                self.handleCallClose()
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
        case .incoming:
            // The callee (we) has accepted the call. Notify the caller.
            self.topic?.videoCall(event: "accept", seq: self.callSeqId)
            if !self.isAudioOnlyCall {
                DispatchQueue.main.async {
                    // Hide peer name & avatar.
                    self.peerNameLabel.alpha = 0
                    self.peerAvatarImageView.alpha = 0
                }
            }
        case .none:
            Cache.log.error("CallVC - Invalid call direction in handleCallInvite()")
        }
    }

    private func playSoundEffect(_ effect: String?, loop: Bool = false) {
        audioPlayer?.stop()

        guard let effect = effect else {
            return
        }

        let path = Bundle.main.path(forResource: "\(effect).m4a", ofType: nil)!
        let url = URL(fileURLWithPath: path)

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            if loop {
                // Play continously.
                audioPlayer?.numberOfLoops = -1
            } else {
                audioPlayer?.numberOfLoops = 0
            }
            audioPlayer?.play()
        } catch {
            Cache.log.error("CallVC - Unable to play sound effect '%@': %@", effect, error.localizedDescription)
        }
    }

    private func dialingAnimation(on: Bool) {
        if on {
            self.addDialingRipple(offset: 10, opacity: 0.4)
            self.addDialingRipple(offset: 30, opacity: 0.2)
            self.addDialingRipple(offset: 60, opacity: 0.1)
        } else {
            self.dialingAnimationContainer.layer.sublayers = nil
        }
    }

    private func addDialingRipple(offset: CGFloat, opacity: Float) {
        let diameter: CGFloat = dialingAnimationContainer.bounds.width

        let layerRipple = CAShapeLayer()
        layerRipple.frame = dialingAnimationContainer.bounds
        layerRipple.path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: dialingAnimationContainer.frame.size)).cgPath
        layerRipple.fillColor = Constants.kDialingAnimationColor
        layerRipple.opacity = opacity

        dialingAnimationContainer.layer.addSublayer(layerRipple)

        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.duration = Constants.kDialingAnimationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.repeatCount = .infinity
        animation.fromValue = CGAffineTransform.identity
        animation.toValue = (diameter + offset) / diameter

        layerRipple.add(animation, forKey: nil)
    }
}

extension CallViewController {
    func embedView(_ addingView: UIView, into containerView: UIView) {
        addingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addingView.frame = containerView.bounds
        containerView.addSubview(addingView)
        containerView.layoutIfNeeded()
    }
}

extension CallViewController: CameraCaptureDelegate {
    func captureVideoOutput(sampleBuffer: CMSampleBuffer) {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let rtcpixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
            let timeStampNs: Int64 = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000000000)
            let videoFrame = RTCVideoFrame(buffer: rtcpixelBuffer, rotation: RTCVideoRotation._0, timeStampNs: timeStampNs)

            webRTCClient.didCaptureLocalFrame(videoFrame)
        }
    }
}

extension CallViewController: WebRTCClientDelegate {
    func sendOffer(withDescription sdp: RTCSessionDescription) {
        self.topic?.videoCall(event: "offer", seq: self.callSeqId, payload: sdp.serialize())
    }

    func sendAnswer(withDescription sdp: RTCSessionDescription) {
        self.topic?.videoCall(event: "answer", seq: self.callSeqId, payload: sdp.serialize())
    }

    func sendIceCandidate(_ candidate: RTCIceCandidate) {
        self.topic?.videoCall(event: "ice-candidate", seq: self.callSeqId, payload: candidate.serialize())
    }

    func closeCall() {
        self.handleCallClose()
    }

    func handleRemoteStream(_ client: WebRTCClient, receivedStream stream: RTCMediaStream) {
        client.setupRemoteRenderer(self.remoteRenderer!, withTrack: stream.videoTracks.first)
    }

    func canSendOffer() -> Bool {
        return self.callDirection != .incoming || self.callInitialSetupComplete
    }

    func enableMediaControls() {
        DispatchQueue.main.async {
            self.micToggleButton.isEnabled = true
            self.videoToggleButton.isEnabled = true
            self.speakerToggleButton.isEnabled = true
        }
    }

    func markConnectionSetupComplete() {
        self.callInitialSetupComplete = true
        self.webRTCClient.drainIceCandidatesCache()
    }

    func toggleRemoteVideo(remoteLive: Bool) {
        DispatchQueue.main.async {
            self.remoteView.isHidden = !remoteLive
            self.peerNameRemoteVideoLabel.isHidden = !remoteLive
            self.peerNameLabel.alpha = !remoteLive ? 1 : 0
            self.peerAvatarImageView.alpha = !remoteLive ? 1 : 0
        }
    }
}

extension CallViewController: TinodeVideoCallDelegate {
    func eventMatchesCallInProgress(info: MsgServerInfo) -> Bool {
        // Make sure it's a "call" info message on the topic & seq of the present call.
        return info.what == "call" && info.topic == self.topic?.name && info.seq == self.callSeqId
    }

    func handleAcceptedMsg() {
        assert(Thread.isMainThread)
        self.playSoundEffect(nil)

        // Stop animation, hide peer name & avatar.
        self.dialingAnimation(on: false)
        if !self.isAudioOnlyCall {
            self.peerNameLabel.alpha = 0
            self.peerAvatarImageView.alpha = 0
        }
        // The callee has informed us (the caller) of the call acceptance.
        guard self.webRTCClient.createPeerConnection(withDataChannel: true) else {
            Cache.log.error("CallVC.handleAcceptedMsg - createPeerConnection failed")
            self.handleCallClose()
            return
        }
    }

    func handleOfferMsg(with payload: JSONValue?) {
        assert(Thread.isMainThread)
        guard case let .dict(offer) = payload, let desc = RTCSessionDescription.deserialize(from: offer) else {
            Cache.log.error("CallVC.handleOfferMsg - invalid offer payload")
            self.handleCallClose()
            return
        }
        // Data channel should be created by the peer. Not creating one.
        guard self.webRTCClient.createPeerConnection(withDataChannel: false) else {
            Cache.log.error("CallVC.handleOfferMsg - createPeerConnection failed")
            self.handleCallClose()
            return
        }
        self.webRTCClient.handleRemoteOfferDescription(desc)
    }

    func handleAnswerMsg(with payload: JSONValue?) {
        assert(Thread.isMainThread)
        guard case let .dict(answer) = payload, let desc = RTCSessionDescription.deserialize(from: answer) else {
            Cache.log.error("CallVC.handleAnswerMsg - invalid answer payload")
            self.handleCallClose()
            return
        }
        self.webRTCClient.handleRemoteAnswerDescription(desc)
    }

    func handleIceCandidateMsg(with payload: JSONValue?) {
        assert(Thread.isMainThread)
        guard case let .dict(iceDict) = payload, let candidate = RTCIceCandidate.deserialize(from: iceDict) else {
            Cache.log.error("CallVC.handleIceCandidateMsg - invalid ICE candidate payload")
            self.handleCallClose()
            return
        }
        self.webRTCClient.handleRemoteIceCandidate(candidate, saveInCache: !self.callInitialSetupComplete)
    }

    func handleRemoteHangup() {
        assert(Thread.isMainThread)
        self.playSoundEffect("call-end")
        self.handleCallClose()
    }

    func handleRinging() {
        assert(Thread.isMainThread)
        self.dialingAnimation(on: true)
        self.playSoundEffect("call-out", loop: true)
    }
}
