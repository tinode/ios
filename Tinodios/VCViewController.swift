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
    lazy var room = Room(delegate: self)

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
        self.endpoint = Cache.tinode.getServerParam(for: "vcEndpoint")!.asString()!
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
            self.topic?.videoCall(event: "vc-join", seq: self.callSeqId)
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

    func joinRoom(withToken token: String) {
        let token: String = token

        room.connect(self.endpoint!, token).then { room in
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
        return (room.localParticipant != nil ? 1 : 0) + self.remoteParticipants.count
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VCViewCell.kIdentifer, for: indexPath) as? VCViewCell
            else { preconditionFailure("Failed to load collection view cell") }

        if indexPath.row == 0 {
            // Local video.
            cell.videoView.track = room.localParticipant?.localVideoTracks.first?.track as? VideoTrack
            cell.peerNameLabel.text = "You"
            cell.peerNameLabel.sizeToFit()
        } else {
            // Remote participants.
            let idx = indexPath.row - 1
            let p = self.remoteParticipants[idx]
            cell.peerNameLabel.text = (Cache.tinode.getUser(with: p.identity) as? User<TheCard>)?.pub?.fn ?? p.identity
            cell.peerNameLabel.sizeToFit()
            cell.videoView.track = p.videoTracks.first?.track as? VideoTrack
        }
        return cell
    }
}

extension VCViewController: RoomDelegate {

    func room(_ room: Room, localParticipant: LocalParticipant, didPublish publication: LocalTrackPublication) {
        DispatchQueue.main.async {
            self.collectionView.reloadItems(at: [IndexPath(row: 0, section: 0)])
        }
    }

    func room(_ room: Room, participant: RemoteParticipant, didSubscribe publication: RemoteTrackPublication, track: Track) {
        if let idx = self.remoteParticipants.firstIndex(where: { $0.sid == participant.sid }) {
            DispatchQueue.main.async {
                self.collectionView.reloadItems(at: [IndexPath(row: idx, section: 0)])
            }
        } else {
            self.remoteParticipants.append(participant)
            DispatchQueue.main.async {
                self.collectionView.insertItems(at: [IndexPath(row: self.collectionView.numberOfItems(inSection: 0), section: 0)])
            }
        }
    }

    func room(_ room: Room, participantDidJoin participant: RemoteParticipant) {
        self.remoteParticipants.append(participant)
        DispatchQueue.main.async {
            self.collectionView.reloadData()
        }
    }

    func room(_ room: Room, participantDidLeave participant: RemoteParticipant) {
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
