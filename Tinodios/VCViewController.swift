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
    class VCRoom: ObservableRoom {
        weak var controller: VCViewController?

        init(withController ctrl: VCViewController) {
            super.init()
            self.controller = ctrl
        }

        var localParticipant: LocalParticipant? {
            return room.localParticipant
        }

        override func room(_ room: Room, participantDidJoin participant: RemoteParticipant) {
            super.room(room, participantDidJoin: participant)
            controller?.remoteParticipants.append(participant)
            DispatchQueue.main.async {
                self.controller?.collectionView.reloadData()
            }
        }

        override func room(_ room: Room, participantDidLeave participant: RemoteParticipant) {
            super.room(room, participantDidLeave: participant)
            controller?.remoteParticipants.removeAll(where: { $0.sid == participant.sid })
            DispatchQueue.main.async {
                self.controller?.collectionView.reloadData()
            }
        }

        override func room(_ room: Room, participant: Participant, didUpdate publication: TrackPublication, muted: Bool) {
            super.room(room, participant: participant, didUpdate: publication, muted: muted)
            if let idx = controller?.remoteParticipants.firstIndex(where: { $0.sid == participant.sid }) {
                DispatchQueue.main.async {
                    if let cell = self.controller?.collectionView.cellForItem(at: IndexPath(row: idx + 1, section: 0)) as? VCViewCell {
                        cell.isMuted = muted
                    }
                }
            }
        }

        override func room(_ room: Room, localParticipant: LocalParticipant, didPublish publication: LocalTrackPublication) {
            super.room(room, localParticipant: localParticipant, didPublish: publication)
            DispatchQueue.main.async {
                self.controller?.collectionView.reloadItems(at: [IndexPath(row: 0, section: 0)])
            }
        }

        override func room(_ room: Room, participant: RemoteParticipant, didSubscribe publication: RemoteTrackPublication, track: Track) {
            super.room(room, participant: participant, didSubscribe: publication, track: track)
            if let idx = controller?.remoteParticipants.firstIndex(where: { $0.sid == participant.sid }) {
                DispatchQueue.main.async {
                    self.controller?.collectionView.reloadItems(at: [IndexPath(row: idx, section: 0)])
                }
            } else {
                controller?.remoteParticipants.append(participant)
                DispatchQueue.main.async {
                    if let ctrl = self.controller {
                        ctrl.collectionView.insertItems(at: [IndexPath(row: ctrl.collectionView.numberOfItems(inSection: 0), section: 0)])
                    }
                }
            }
        }
    }

    weak var topic: DefaultComTopic?
    var callDirection: CallViewController.CallDirection = .none
    var callSeqId: Int = -1
    // VC info messages listener.
    var listener: InfoListener!
    var remoteParticipants = [RemoteParticipant]()

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

    var endpoint: String?
    lazy var room = VCRoom(withController: self)//Room(delegate: self)

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
        self.endpoint = Cache.tinode.getServerParam(for: "vcEndpoint")?.asString()
    }

    override func viewDidAppear(_ animated: Bool) {
        Cache.tinode.addListener(self.listener)
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

    override func viewDidDisappear(_ animated: Bool) {
        Cache.tinode.removeListener(self.listener)
    }

    @IBAction func didTapHangUp(_ sender: Any) {
        self.handleCallClose()
    }

    @IBAction func didTapToggleLoudspeaker(_ sender: Any) {
        //self.room.loud
    }

    @IBAction func didTapToggleAudio(_ sender: Any) {
        self.room.toggleMicrophoneEnabled()
    }

    @IBAction func didTapToggleVideo(_ sender: Any) {
        self.room.toggleCameraEnabled()
    }

    func joinRoom(withToken token: String) {
        let token: String = token

        room.room.connect(self.endpoint!, token).then { room in
            // Publish camera & mic
            room.localParticipant?.setCamera(enabled: true)
            room.localParticipant?.setMicrophone(enabled: true)
        }.catch { error in
            // failed to connect
            print(error)
        }
    }

    func handleCallClose() {
        if self.callSeqId > 0 {
            self.topic?.videoCall(event: "hang-up", seq: self.callSeqId)
        }
        self.room.room.disconnect()
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
        return (room.room.localParticipant != nil ? 1 : 0) + self.remoteParticipants.count
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VCViewCell.kIdentifer, for: indexPath) as? VCViewCell
            else { preconditionFailure("Failed to load collection view cell") }

        if indexPath.row == 0 {
            // Local video.
            cell.videoView.track = room.localParticipant?.localVideoTracks.first?.track as? VideoTrack
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

            let pub = (Cache.tinode.getUser(with: p.identity) as? User<TheCard>)?.pub
            // Avatar.
            cell.avatarView.set(pub: pub, id: p.identity, deleted: false)
            cell.avatarView.letterTileFont = cell.avatarView.letterTileFont.withSize(CGFloat(50))

            cell.peerNameLabel.text = pub?.fn ?? p.identity
            cell.peerNameLabel.sizeToFit()
            cell.videoView.track = p.videoTracks.first?.track as? VideoTrack
        }
        return cell
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
