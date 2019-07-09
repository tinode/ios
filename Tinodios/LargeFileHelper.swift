//
//  LargeFileHelper.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit
import TinodeSDK

class Upload {
    var url: URL
    var topicId: String
    var msgId: Int64 = 0
    var isUploading = false
    var progress: Float = 0
    var responseData: Data = Data()
    var callback: ((ServerMessage) -> Void)?

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
    func startUpload(filename: String, mimetype: String, d: Data, topicId: String, msgId: Int64,
                     completionCallback: ((ServerMessage) -> Void)?) {
        let tinode = Cache.getTinode()
        guard var url = tinode.baseURL(useWebsocketProtocol: false) else { return }
        url.appendPathComponent("file/u/")
        let upload = Upload(url: url)
        var request = URLRequest(url: url)

        request.httpMethod = "POST"
        request.addValue("Keep-Alive", forHTTPHeaderField: "Connection")
        request.addValue(tinode.userAgent, forHTTPHeaderField: "User-Agent")
        request.addValue("multipart/form-data; boundary=\(LargeFileHelper.kBoundary)", forHTTPHeaderField: "Content-Type")
        request.addValue(tinode.apiKey, forHTTPHeaderField: "X-Tinode-APIKey")
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
        let localFileName = UUID().uuidString
        let localURL = tempDir.appendingPathComponent("throwaway-\(localFileName)")
        try? newData.write(to: localURL)

        upload.task = uploadSession.uploadTask(with: request, fromFile: localURL)
        upload.task!.taskDescription = localFileName
        upload.isUploading = true
        upload.topicId = topicId
        upload.msgId = msgId
        upload.callback = completionCallback
        upload.task!.resume()
        activeUploads[localFileName] = upload
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
extension LargeFileHelper: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive: Data) {
        if let taskId = dataTask.taskDescription, let upload = activeUploads[taskId] {
            print("working with task \(taskId) - \(upload.topicId)")
            upload.responseData.append(didReceive)
        }
    }
}
extension LargeFileHelper: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError: Error?) {
        print("We're done here")
        if let error = didCompleteWithError {
            print("Quit with \(error) - \(task.taskDescription)")
            return
        }
        // activeUploads.removeValue(forKey: )
        if let taskId = task.taskDescription, let upload = activeUploads[taskId] {
            activeUploads.removeValue(forKey: taskId)
            print("done with task \(taskId) - \(upload.topicId)")
            let tinode = Cache.getTinode()
            let topic = tinode.getTopic(topicName: upload.topicId) as! DefaultComTopic

            if let response = task.response as? HTTPURLResponse {
                //
                if response.statusCode == 200 && !upload.responseData.isEmpty {
                    print("response \(response)")
                    if let serverMsg = try? Tinode.jsonDecoder.decode(ServerMessage.self, from: upload.responseData) {
                        upload.callback?(serverMsg)
                    }
                } else {
                    print("failed - \(response.statusCode) \(response.allHeaderFields) \(upload.responseData.count)")
                }
                print("mime type = \(response.mimeType)")
            }
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        Thread.sleep(forTimeInterval: 0.1)
        if let t = task.taskDescription, let upload = activeUploads[t] {
            print("\(upload.topicId): sent = \(totalBytesSent), expected = \(totalBytesExpectedToSend)")
        }
    }
}
