//
//  QRScanner.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import AVFoundation
import UIKit

protocol QRScannerDelegate: AnyObject {
    func qrScanner(didScanCode codeValue: String?)
}

// QR code scanner.
class QRScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private var captureSession: AVCaptureSession!
    private weak var cameraPreviewView: UIView!
    // Scanned codes not starting with prefix will be dropped.
    private var expectedCodePrefix: String?
    private weak var delegate: QRScannerDelegate?

    init(embedIn cameraView: UIView!, expectedCodePrefix: String?, delegate: QRScannerDelegate?) {
        self.cameraPreviewView = cameraView
        self.expectedCodePrefix = expectedCodePrefix
        self.delegate = delegate
    }

    deinit {
        stop()
    }

    func stop() {
        if let cs = self.captureSession, cs.isRunning {
            cs.stopRunning()
        }
    }

    func start() {
        if let cs = captureSession {
            DispatchQueue.global(qos: .background).async {
                if !cs.isRunning {
                    cs.startRunning()
                }
            }
            return
        }

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            Cache.log.info("Failed to get default capture device for video")
            scanFailed()
            return
        }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            Cache.log.info("Failed to obtain video input")
            scanFailed()
            return
        }

        captureSession = AVCaptureSession()
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            Cache.log.info("Failed to add video input")
            scanFailed()
            captureSession = nil
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            Cache.log.info("Failed to add video output")
            scanFailed()
            captureSession = nil
            return
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = cameraPreviewView.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        cameraPreviewView.layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
    }

    // Makes sure `code` has the expected prefix.
    // If so, strips the prefix from `code`.
    // Else, returns nil.
    private func validateCodePrefix(_ code: String) -> String? {
        guard let prefix = self.expectedCodePrefix, !prefix.isEmpty else {
            // No expected prefix. Use code as is.
            return code
        }
        if !code.hasPrefix(prefix) {
            // Invalid code.
            return nil
        }
        return String(code.dropFirst(prefix.count))
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            self.delegate?.qrScanner(didScanCode: self.validateCodePrefix(stringValue))
        }
    }

    func scanFailed() {
        UiUtils.showToast(message: NSLocalizedString("QRCode scanner failed to initialize", comment: "Error message when QR code scanner failed to init"))
    }
}
