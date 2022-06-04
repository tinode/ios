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

        // Add a video data output
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
            videoDataOutput.connection(with: .video)?.videoOrientation = .portrait
            videoDataOutput.connection(with: .video)?.automaticallyAdjustsVideoMirroring = false
            videoDataOutput.connection(with: .video)?.isVideoMirrored = true
        } else {
            print("Could not add video data output to the session")
            captureSession.commitConfiguration()
        }
    }

    func startCapture() {
        print("CameraManager: start capture")

        guard !isCapturing else { return }
        isCapturing = true

        #if arch(arm64)
        captureSession.startRunning()
        #endif
    }
    func stopCapture() {
        print("CameraManager: end capture")
        guard isCapturing else { return }
        isCapturing = false

        #if arch(arm64)
        captureSession.stopRunning()
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
}

/// TinodeVideoCallDelegate
/// Methods for handling remote messages received from the peer.
protocol TinodeVideoCallDelegate: AnyObject {
    func handleAcceptedMsg()
    func handleOfferMsg(with payload: JSONValue?)
    func handleAnswerMsg(with payload: JSONValue?)
    func handleIceCandidateMsg(with payload: JSONValue?)
    func handleRemoteHangup()
}

class WebRTCClient: NSObject {
    static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    private let mediaConstraints = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                                   kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue]

    public var localPeer: RTCPeerConnection?
    private var localVideoSource: RTCVideoSource?
    private var localVideoTrack: RTCVideoTrack?
    private var videoCapturer: RTCVideoCapturer?
    public var remoteVideoTrack: RTCVideoTrack?

    private var localAudioTrack: RTCAudioTrack?

    weak var delegate: WebRTCClientDelegate?

    func setup() {
        createMediaSenders()
        configureAudioSession()
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

    func createPeerConnection() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let config = generateRTCConfig()

        localPeer = WebRTCClient.factory.peerConnection(with: config, constraints: constraints, delegate: self)

        let stream = WebRTCClient.factory.mediaStream(withStreamId: "ARDAMS")
        stream.addAudioTrack(self.localAudioTrack!)
        stream.addVideoTrack(self.localVideoTrack!)
        localPeer!.add(stream)
    }

    func offer(_ peerConnection: RTCPeerConnection) {
        print("WebRTCClient: sending offer.")
        peerConnection.offer(for: RTCMediaConstraints(mandatoryConstraints: mediaConstraints, optionalConstraints: nil), completionHandler: { [weak self](sdp, error) in
            guard let self = self else { return }

            guard let sdp = sdp else {
                // Missing SDP.
                if let error = error {
                    print(error)
                }
                self.delegate?.closeCall()
                return
            }

            peerConnection.setLocalDescription(sdp, completionHandler: { (error) in
                if let error = error {
                    debugPrint(error)
                    self.delegate?.closeCall()
                    return
                }
                self.delegate?.sendOffer(withDescription: sdp)
            })
        })
    }

    func answer(_ peerConnection: RTCPeerConnection) {
        print("WebRTCClient: sending answer.")
        peerConnection.answer(
            for: RTCMediaConstraints(mandatoryConstraints: self.mediaConstraints, optionalConstraints: nil),
            completionHandler: { [weak self](sdp, error) in
                guard let self = self, let sdp = sdp else {
                    if let error = error {
                        print("answer() failure: \(error)")
                    }
                    self?.delegate?.closeCall()
                    return
                }

                peerConnection.setLocalDescription(sdp, completionHandler: { [weak self](error) in
                    if let error = error {
                        print("answer.setLocalDescription() failure: \(error)")
                        self?.delegate?.closeCall()
                        return
                    }
                    print("actually sending answer \(sdp)")
                    self?.delegate?.sendAnswer(withDescription: sdp)
                    self?.delegate?.markConnectionSetupComplete()
                })
            })
    }

    func disconnect() {
        localPeer?.close()

        localPeer = nil
        localVideoSource = nil
        localVideoTrack = nil
        videoCapturer = nil
        remoteVideoTrack = nil
    }
}

// MARK: Preparation/setup.
extension WebRTCClient {
    // TODO: ICE/WebRTC config should be obtained from the server.
    private func generateRTCConfig() -> RTCConfiguration {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:bn-turn1.xirsys.com"])]
        config.iceServers.append(RTCIceServer(
            urlStrings: [
                "turn:bn-turn1.xirsys.com:80?transport=udp",
                "turn:bn-turn1.xirsys.com:3478?transport=udp",
                "turn:bn-turn1.xirsys.com:80?transport=tcp",
                "turn:bn-turn1.xirsys.com:3478?transport=tcp",
                "turns:bn-turn1.xirsys.com:443?transport=tcp",
                "turns:bn-turn1.xirsys.com:5349?transport=tcp"],
            username: "0kYXFmQL9xojOrUy4VFemlTnNPVFZpp7jfPjpB3AjxahuRe4QWrCs6Ll1vDc7TTjAAAAAGAG2whXZWJUdXRzUGx1cw==",
            credential: "285ff060-5a58-11eb-b269-0242ac140004"))
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

    private func configureAudioSession() {
        let audioSession = RTCAudioSession.sharedInstance()

        audioSession.lockForConfiguration()
        do {
            try audioSession.setCategory(AVAudioSession.Category.playAndRecord.rawValue)
            try audioSession.setMode(AVAudioSession.Mode.voiceChat.rawValue)
            try audioSession.overrideOutputAudioPort(.speaker)
            try audioSession.setActive(true)
        } catch let error {
            print("WebRTCClient: error setting AVAudioSession category: \(error)")
        }
        audioSession.unlockForConfiguration()
    }
}

// MARK: UI Handling
extension WebRTCClient {
    func setupLocalRenderer(_ renderer: RTCVideoRenderer) {
        guard let localVideoTrack = localVideoTrack else { return }
        localVideoTrack.add(renderer)
    }

    func setupRemoteRenderer(_ renderer: RTCVideoRenderer) {
        guard let remoteVideoTrack = remoteVideoTrack else { return }
        remoteVideoTrack.add(renderer)
    }

    func didCaptureLocalFrame(_ videoFrame: RTCVideoFrame) {
        guard let videoSource = localVideoSource,
            let videoCapturer = videoCapturer else { return }
        videoSource.capturer(videoCapturer, didCapture: videoFrame)
    }
}

// MARK: Message Handling
extension WebRTCClient {
    func handleRemoteDescription(_ desc: RTCSessionDescription) {
        guard let peerConnection = localPeer else { return }
        peerConnection.setRemoteDescription(desc, completionHandler: { [weak self](error) in
            guard let self = self else { return }
            if let error = error {
                print("handleRemoteDescription.setRemoteDescription failure: \(error)")
                self.delegate?.closeCall()
                return
            }

            self.answer(peerConnection)
        })
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("state changed \(stateChanged)")
        if stateChanged == .closed {
            self.delegate?.closeCall()
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("Received remote stream")
        self.delegate?.handleRemoteStream(self, receivedStream: stream)
        print("added remote stream - done")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("removing media stream")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("should negotiate")
        guard self.delegate?.canSendOffer() ?? false else {
            return
        }
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
        print("rtc gathering state \(newState)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("did generate ice candidate \(candidate)")
        self.delegate?.sendIceCandidate(candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("did remove ice cands")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("did open data channel")
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
        static let kActionButtonSize = 50
        static let kEndCallIcon = "phone.down"
        static let kToggleCameraIcon = "video"
        static let kToggleMicIcon = "mic"
    }

    enum CallDirection {
        case none
        case outgoing
        case incoming
    }

    @IBOutlet weak var remoteView: UIView!
    @IBOutlet weak var localView: UIView!

    private static func actionButtonIcon(iconName: String) -> UIImage? {
        return UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .light))
    }

    private static func makeActionButton(withBkgColor bkgColor: UIColor, iconName: String) -> UIButton {
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: Constants.kActionButtonSize, height: Constants.kActionButtonSize))
        button.backgroundColor = bkgColor
        let img = actionButtonIcon(iconName: iconName)
        button.setImage(img, for: .normal)
        button.tintColor = .white
        button.layer.cornerRadius = CGFloat(Constants.kActionButtonSize / 2)
        return button
    }

    // Action buttons displayed at the bottom (mute audio/video, end call).
    private let endCallButton = makeActionButton(withBkgColor: UIColor.systemRed, iconName: Constants.kEndCallIcon)
    private let toggleCameraButton = makeActionButton(withBkgColor: UIColor.systemGray, iconName: Constants.kToggleCameraIcon)
    private let toggleMicButton = makeActionButton(withBkgColor: UIColor.systemGray, iconName: Constants.kToggleMicIcon)

    weak var topic: DefaultComTopic?
    let cameraManager = CameraManager()
    let webRTCClient = WebRTCClient()
    // Peer messasges listener.
    var listener: InfoListener!

    var remoteRenderer: RTCVideoRenderer?

    var callDirection: CallDirection = .none
    var callSeqId: Int = -1
    // If true, the client has received a remote SDP from the peer and has sent a local SDP to the peer.
    var callInitialSetupComplete = false

    class InfoListener: UiTinodeEventListener {
        private weak var delegate: TinodeVideoCallDelegate?
        init(delegateEventsTo callDelegate: TinodeVideoCallDelegate, connected: Bool) {
            super.init(connected: connected)
            self.delegate = callDelegate
        }

        override func onInfoMessage(info: MsgServerInfo?) {
            guard let info = info, info.what == "call" else { return }
            switch info.event {
            case "accept":
                self.delegate?.handleAcceptedMsg()
            case "offer":
                self.delegate?.handleOfferMsg(with: info.payload)
            case "answer":
                self.delegate?.handleAnswerMsg(with: info.payload)
            case "ice-candidate":
                self.delegate?.handleIceCandidateMsg(with: info.payload)
            case "hang-up":
                self.delegate?.handleRemoteHangup()
            default:
                print(info)
            }
        }
    }

    override func viewDidLoad() {
        self.view.addSubview(self.toggleCameraButton)
        self.view.addSubview(self.toggleMicButton)
        self.view.addSubview(self.endCallButton)
        self.endCallButton.addTarget(self, action: #selector(didTapEndCall), for: .touchUpInside)
        self.toggleCameraButton.addTarget(self, action: #selector(didTapToggleCamera), for: .touchUpInside)
        self.toggleMicButton.addTarget(self, action: #selector(didTapToggleMic), for: .touchUpInside)

        self.listener = InfoListener(delegateEventsTo: self, connected: Cache.tinode.isConnected)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let totalWidth = self.view.frame.size.width / 2
        let x1 = Int(totalWidth - 1.5 * CGFloat(Constants.kActionButtonSize) - 20)
        let x2 = Int(totalWidth - 0.5 * CGFloat(Constants.kActionButtonSize))
        let x3 = Int(totalWidth + 0.5 * CGFloat(Constants.kActionButtonSize) + 20)
        let y = Int(self.view.frame.size.height) - 60

        self.toggleCameraButton.frame.origin = CGPoint(x: x1, y: y)
        self.toggleMicButton.frame.origin = CGPoint(x: x2, y: y)
        self.endCallButton.frame.origin = CGPoint(x: x3, y: y)
    }

    @objc private func didTapEndCall() {
        self.handleCallClose()
    }

    @objc private func didTapToggleCamera() {
        var iconName = Constants.kToggleCameraIcon
        if !self.webRTCClient.toggleVideo() {
            iconName += ".slash"
        }
        let img = CallViewController.actionButtonIcon(iconName: iconName)
        self.toggleCameraButton.setImage(img, for: .normal)
    }

    @objc private func didTapToggleMic() {
        var iconName = Constants.kToggleMicIcon
        if !self.webRTCClient.toggleAudio() {
            iconName += ".slash"
        }
        let img = CallViewController.actionButtonIcon(iconName: iconName)
        self.toggleMicButton.setImage(img, for: .normal)
    }

    private func setupCaptureSessionAndStartCall() {
        cameraManager.setupCamera()
        cameraManager.startCapture()
        setupViews()

        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil, using: handleRouteChange)

        webRTCClient.delegate = self
        cameraManager.delegate = self
        Cache.tinode.addListener(self.listener)

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

    override func viewDidAppear(_ animated: Bool) {
        self.checkCameraPermissions { success in
            if success {
                self.checkMicPermissions { success in
                    if success {
                        DispatchQueue.main.async { self.setupCaptureSessionAndStartCall() }
                    } else {
                        DispatchQueue.main.async { self.handleCallClose() }
                    }
                }
            } else {
                DispatchQueue.main.async { self.handleCallClose() }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
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
            try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        case .oldDeviceUnavailable:
            try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        default:
            print("routeChange: other - \(reason)")
        }
    }

    func setupViews() {
        #if arch(arm64)
            // Using metal (arm64 only)
            let localRenderer = RTCMTLVideoView(frame: self.localView.frame)
            let remoteRenderer = RTCMTLVideoView(frame: self.remoteView.frame)
            localRenderer.videoContentMode = .scaleAspectFill
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
    }

    func stopMedia() {
        self.webRTCClient.disconnect()
        cameraManager.stopCapture()
    }

    func handleCallClose() {
        if self.callSeqId > 0 {
            self.topic?.videoCall(event: "hang-up", seq: self.callSeqId)
            Cache.callManager.completeCallInProgress(reportToSystem: true, reportToPeer: false)
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
            // Send out a call invitation to the peer.
            self.topic?.publish(content: Drafty.videoCall(),
                                withExtraHeaders:["webrtc": .string("started")]).then(onSuccess: { msg in
                guard let ctrl = msg?.ctrl else { return nil }
                if ctrl.code < 300, let seq = ctrl.getIntParam(for: "seq"), seq > 0 {
                    // All good.
                    self.callSeqId = seq
                    return nil
                }
                self.handleCallClose()
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
        case .incoming:
            // The callee (we) has accepted the call. Notify the caller.
            self.topic?.videoCall(event: "accept", seq: self.callSeqId)
        case .none:
            print("Invalid call direction in handleCallInvite()")
        }
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
        client.remoteVideoTrack = stream.videoTracks.first
        self.webRTCClient.setupRemoteRenderer(self.remoteRenderer!)
    }

    func canSendOffer() -> Bool {
        return self.callDirection != .incoming || self.callInitialSetupComplete
    }

    func markConnectionSetupComplete() {
        self.callInitialSetupComplete = true
    }
}

extension CallViewController: TinodeVideoCallDelegate {
    func handleAcceptedMsg() {
        // The callee has informed us (the caller) of the call acceptance.
        self.webRTCClient.createPeerConnection()
    }
    
    func handleOfferMsg(with payload: JSONValue?) {
        guard case let .dict(offer) = payload, let desc = RTCSessionDescription.deserialize(from: offer) else {
            print("invalid offer payload")
            self.handleCallClose()
            return
        }
        self.webRTCClient.createPeerConnection()
        self.webRTCClient.handleRemoteDescription(desc)
    }
    
    func handleAnswerMsg(with payload: JSONValue?) {
        guard case let .dict(answer) = payload, let desc = RTCSessionDescription.deserialize(from: answer) else {
            print("empty/invalid answer payload")
            self.handleCallClose()
            return
        }
        self.webRTCClient.localPeer?.setRemoteDescription(desc, completionHandler: { (error) in
            if let e = error {
                print("error setting remote description \(e)")
                self.handleCallClose()
            }
            if self.callDirection == .outgoing {
                self.markConnectionSetupComplete()
            }
        })
    }
    
    func handleIceCandidateMsg(with payload: JSONValue?) {
        guard case let .dict(iceDict) = payload, let candidate = RTCIceCandidate.deserialize(from: iceDict) else {
            print("empty/invalid ICE candidate payload")
            self.handleCallClose()
            return
        }
        self.webRTCClient.localPeer?.add(candidate)
    }
    
    func handleRemoteHangup() {
        self.handleCallClose()
    }
}
