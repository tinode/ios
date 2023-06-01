//
//  VCViewController.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import LiveKitClient
import TinodeSDK
import UIKit

protocol VCCallDelegate: AnyObject {
    func eventMatchesVCCall(info: MsgServerInfo) -> Bool
    func handleVCToken(with payload: JSONValue?)
    func handleRemoteHangup()
}

struct VCJoinRequest {
    let topic: String
    let seq: Int
}

class VCViewController: UIViewController {
    @IBOutlet weak var muteAudioButton: UIButton!
    @IBOutlet weak var muteVideoButton: UIButton!
    weak var topic: DefaultComTopic?
    var callDirection: CallViewController.CallDirection = .none
    var callSeqId: Int = -1
    // VC info messages listener.
    var listener: InfoListener!
    private var remoteParticipants = [RemoteParticipant]()
    private var timer: Timer!
    private var cellReference = NSHashTable<VCViewCell>.weakObjects()
    private var endpoint: String?
    private lazy var room = Room(delegate: self)

    // Media controls.
    private var cameraEnabled: Bool {
        get { return room.localParticipant?.isCameraEnabled() ?? false }
        set {
            room.localParticipant?.setCamera(enabled: newValue).then(on: DispatchQueue.main) { _ in
                //self.updateControlButtons()
                self.muteVideoButton.setImage(UIImage(systemName: self.cameraEnabled ? "vc.fill" : "vc.slash.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)), for: .normal)
            }
        }
    }
    private var micEnabled: Bool {
        get { return room.localParticipant?.isMicrophoneEnabled() ?? false }
        set {
            room.localParticipant?.setMicrophone(enabled: newValue).then(on: DispatchQueue.main) { _ in
                //self.updateControlButtons()
                self.muteAudioButton.setImage(UIImage(systemName: self.micEnabled ? "mic.fill" : "mic.slash.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)), for: .normal)
            }
        }
    }

    @IBOutlet weak var collectionView: UICollectionView!

    class InfoListener: TinodeEventListener {
        private weak var delegate: VCCallDelegate?
        init(delegateEventsTo callDelegate: VCCallDelegate) {
            self.delegate = callDelegate
        }

        func onInfoMessage(info: MsgServerInfo?) {
            guard let info = info, self.delegate?.eventMatchesVCCall(info: info) ?? false else { return }
            switch info.event {
            case "vc-token":
                DispatchQueue.main.async { self.delegate?.handleVCToken(with: info.payload) }
            case "hang-up":
                DispatchQueue.main.async { self.delegate?.handleRemoteHangup() }
            default:
                print(info)
            }
        }
    }

    deinit {
        self.timer.invalidate()
        Cache.tinode.removeListener(self.listener)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let vcLayout = VCViewLayout()
        collectionView.setCollectionViewLayout(vcLayout, animated: false)
        collectionView.alwaysBounceVertical = true
        collectionView.indicatorStyle = .white
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(VCViewCell.self, forCellWithReuseIdentifier: VCViewCell.kIdentifer)

        view.backgroundColor = .white
        self.listener = InfoListener(delegateEventsTo: self)
        Cache.tinode.addListener(self.listener)
        self.endpoint = Cache.tinode.getServerParam(for: "vcEndpoint")?.asString()
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { [weak self] _ in
            guard let self = self else { return }
            self.updateVideoViews()
        })
        // Start the call.
        start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        self.handleCallClose()
    }

    @IBAction func didTapHangUp(_ sender: Any) {
        self.handleCallClose()
    }

    @IBAction func didTapToggleAudio(_ sender: Any) {
        micEnabled = !micEnabled
    }

    @IBAction func didTapToggleVideo(_ sender: Any) {
        cameraEnabled = !cameraEnabled
    }

    private func start() {
        switch self.callDirection {
        case .outgoing:
            self.topic?.publish(content: Drafty.videoCall(),
                                withExtraHeaders:["webrtc": .string(MsgServerData.WebRTC.kStarted.rawValue),
                                                  "vc": .bool(true)]).then(onSuccess: { msg in
                guard let ctrl = msg?.ctrl else { return nil }
                if ctrl.code < 300, let seq = ctrl.getIntParam(for: "seq"), seq > 0, let token = ctrl.getStringParam(for: "token") {
                    // All good. Register the call.
                    self.callSeqId = seq
                    self.joinRoom(withToken: token)
                    return nil
                }
                self.handleCallClose()
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
        case .incoming:
            if self.endpoint != nil {
                self.topic?.videoCall(event: "vc-join", seq: self.callSeqId)
            }
        default:
            break
        }
    }

    private func setParticipants() {
        self.remoteParticipants = Array(room.remoteParticipants.values)
        self.collectionView.reloadData()
    }

    private func updateVideoViews() {
        let visibleCells = self.collectionView.visibleCells.compactMap { $0 as? VCViewCell }
        let offScreenCells = self.cellReference.allObjects.filter { !visibleCells.contains($0) }

        for cell in visibleCells.filter({ !$0.videoView.isEnabled }) {
            cell.videoView.isEnabled = true
        }

        for cell in offScreenCells.filter({ $0.videoView.isEnabled }) {
            cell.videoView.isEnabled = false
        }
    }

    func joinRoom(withToken token: String) {
        let token: String = token

        room.connect(self.endpoint!, token).then { room in
            // Publish camera & mic
            self.muteAudioButton.isEnabled = true
            self.muteVideoButton.isEnabled = true
            self.micEnabled = true
            self.cameraEnabled = true
            self.setParticipants()
        }.catch { error in
            // failed to connect
            print(error)
        }
    }

    func handleCallClose() {
        if self.callSeqId > 0 {
            self.topic?.videoCall(event: "hang-up", seq: self.callSeqId)
        }
        self.room.disconnect()
        self.callSeqId = -1
        self.remoteParticipants.removeAll()
        DispatchQueue.main.async {
            // Dismiss video call VC.
            self.navigationController?.popViewController(animated: true)
        }
    }
}

extension VCViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return (self.room.localParticipant != nil ? 1 : 0) + self.remoteParticipants.count
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VCViewCell.kIdentifer, for: indexPath) as? VCViewCell
            else { preconditionFailure("Failed to load collection view cell") }

        cellReference.add(cell)
        if indexPath.row == 0 {
            // Local video.
            cell.participant = room.localParticipant
            // Avatar.
            let me = Cache.tinode.getMeTopic()
            cell.avatarView.set(pub: me?.pub, id: Cache.tinode.myUid, deleted: false)
            cell.avatarView.letterTileFont = cell.avatarView.letterTileFont.withSize(CGFloat(50))

            cell.peerNameLabel.text = "You"
            cell.peerNameLabel.sizeToFit()
        } else {
            // Remote participants.
            let idx = indexPath.row - 1
            let p = self.remoteParticipants[idx]
            cell.participant = p

            let pub = (Cache.tinode.getUser(with: p.identity) as? User<TheCard>)?.pub
            // Avatar.
            cell.avatarView.set(pub: pub, id: p.identity, deleted: false)
            cell.avatarView.letterTileFont = cell.avatarView.letterTileFont.withSize(CGFloat(50))

            cell.peerNameLabel.text = pub?.fn ?? p.identity
            cell.peerNameLabel.sizeToFit()
        }
        return cell
    }
}

extension VCViewController: RoomDelegateObjC {
    func room(_ room: Room, participantDidJoin participant: RemoteParticipant) {
        print("participant did join -> \(participant)")
        self.remoteParticipants.append(participant)
        DispatchQueue.main.async {
            self.collectionView.reloadData()
        }
    }

    func room(_ room: Room, participantDidLeave participant: RemoteParticipant) {
        print("participant did leave -> \(participant)")
        self.remoteParticipants.removeAll(where: { $0.sid == participant.sid })
        DispatchQueue.main.async {
            self.collectionView.reloadData()
        }
    }
}

extension VCViewController: VCCallDelegate {
    func eventMatchesVCCall(info: MsgServerInfo) -> Bool {
        // Make sure it's a "call" info message on the topic & seq of the present call.
        return info.what == "call" && info.topic == self.topic?.name && info.seq == self.callSeqId
    }

    func handleVCToken(with payload: JSONValue?) {
        assert(Thread.isMainThread)
        guard case let .dict(dd) = payload, let token = dd["token"]?.asString() else {
            Cache.log.error("VCController.handleVCToken - invalid token")
            self.handleCallClose()
            return
        }
        joinRoom(withToken: token)
    }

    func handleRemoteHangup() {
        assert(Thread.isMainThread)
        self.handleCallClose()
    }
}
