//
//  LargeFileHelper.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

class Upload {
    var url: URL
    var topicId: String
    var msgId: Int = 0
    var isUploading = false
    var progress: Float = 0

    var task: URLSessionUploadTask?

    init(url: URL) {
        self.url = url
        self.topicId = ""
    }
}

class LargeFileHelper: NSObject {
    static let kBoundary = "*****\(Int64(Date().timeIntervalSince1970 as Double * 1000))*****"
    static let kTwoHyphens = "--"
    static let kLineEnd = "\r\n"

    var uploadSession: URLSession!
    var activeUploads: [String : Upload] = [:]
    init(config: URLSessionConfiguration) {
        super.init()
        self.uploadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    convenience override init() {
        let config = URLSessionConfiguration.background(withIdentifier: Bundle.main.bundleIdentifier!)
        self.init(config: config)
    }
    func startUpload(filename: String, mimetype: String, d: Data) {
        let tinode = Cache.getTinode()
        guard var url = tinode.baseURL(useWebsocketProtocol: false) else { return }
        url.appendPathComponent("file/u/")
        let upload = Upload(url: url)
        var request = URLRequest(url: url)

        request.addValue("Keep-Alive", forHTTPHeaderField: "Connection")
        request.addValue(tinode.userAgent, forHTTPHeaderField: "User-Agent")
        request.addValue("multipart/form-data; boundary=\(LargeFileHelper.kBoundary)", forHTTPHeaderField: "Content-Type")
        request.addValue(tinode.apiKey, forHTTPHeaderField: "Content-Type")
        request.addValue("Token \(tinode.authToken!)", forHTTPHeaderField: "Authorization")

        var newData = Data()
        let header = LargeFileHelper.kTwoHyphens + LargeFileHelper.kBoundary + LargeFileHelper.kLineEnd +
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"" + LargeFileHelper.kLineEnd +
            "Content-Type: \(mimetype)" + LargeFileHelper.kLineEnd +
            "Content-Transfer-Encoding: binary" + LargeFileHelper.kLineEnd + LargeFileHelper.kLineEnd
        newData.append(contentsOf: header.utf8)
        newData.append(d)
        let footer = LargeFileHelper.kLineEnd + LargeFileHelper.kTwoHyphens + LargeFileHelper.kBoundary + LargeFileHelper.kTwoHyphens + LargeFileHelper.kLineEnd
        newData.append(contentsOf: footer.utf8)

        var tempDir: URL
        if #available(iOS 10.0, *) {
            tempDir = FileManager.default.temporaryDirectory
        } else {
            // Fallback on earlier versions
            tempDir = URL(string: NSTemporaryDirectory().appending("/dummy"))!
        }
        let localURL = tempDir.appendingPathComponent("throwaway-\(UUID().uuidString)")
        try? newData.write(to: localURL)

        upload.task = uploadSession.uploadTask(with: request, fromFile: localURL)
        upload.task!.resume()
        upload.isUploading = true
        activeUploads[upload.url.absoluteString] = upload
    }
}

extension LargeFileHelper: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
                let completionHandler = appDelegate.backgroundSessionCompletionHandler {
                appDelegate.backgroundSessionCompletionHandler = nil
                completionHandler()
            }
        }
    }
}
extension LargeFileHelper: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError: Error?) {
        print("We're done here")
        // activeUploads.removeValue(forKey: )
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if let t = task.originalRequest?.url {
            print("\(t): sent = \(totalBytesSent), expected = \(totalBytesExpectedToSend)")
        }
    }
}
