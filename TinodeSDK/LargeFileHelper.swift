//
//  LargeFileHelper.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

public class Upload {
    var url: URL
    var topicId: String
    var msgId: Int64 = 0
    var isUploading = false
    var progress: Float = 0
    var responseData: Data = Data()
    var progressCb: ((Float) -> Void)?
    var finalCb: ((ServerMessage?, Error?) -> Void)?

    var task: URLSessionUploadTask?

    init(url: URL) {
        self.url = url
        self.topicId = ""
    }
    deinit {
        if let cb = finalCb {
            cb(nil, TinodeError.invalidState("Topic \(topicId), msg id \(msgId): Could not finish upload. Cancelling."))
        }
    }

    public func appendResponse(_ other: Data) {
        self.responseData.append(other)
    }
}

public class LargeFileHelper: NSObject {
    static let kBoundary = "*****\(Int64((Date().timeIntervalSince1970 * 1000.0).rounded()))*****"
    static let kTwoHyphens = "--"
    static let kLineEnd = "\r\n"

    var urlSession: URLSession!
    var activeUploads: [String : Upload] = [:]
    var tinode: Tinode!

    init(with tinode: Tinode, sessionDelegate delegate: URLSessionDelegate, config: URLSessionConfiguration) {
        super.init()
        self.urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.tinode = tinode
    }
    convenience init(with tinode: Tinode, sessionDelegate delegate: URLSessionDelegate) {
        let config = URLSessionConfiguration.background(withIdentifier: Bundle.main.bundleIdentifier!)
        self.init(with: tinode, sessionDelegate: delegate, config: config)
    }

    public static func addCommonHeaders(to request: inout URLRequest, using tinode: Tinode) {
        request.addValue(tinode.apiKey, forHTTPHeaderField: "X-Tinode-APIKey")
        request.addValue("Token \(tinode.authToken!)", forHTTPHeaderField: "X-Tinode-Auth")
    }

    public static func createUploadKey(topicId: String, msgId: Int64) -> String {
        return "\(topicId)-\(msgId)"
    }

    public func startUpload(filename: String, mimetype: String, d: Data, topicId: String, msgId: Int64,
                     progressCallback: @escaping (Float) -> Void,
                     completionCallback: @escaping (ServerMessage?, Error?) -> Void) {
        guard var url = tinode.baseURL(useWebsocketProtocol: false) else { return }
        url.appendPathComponent("file/u/")
        let upload = Upload(url: url)
        var request = URLRequest(url: url)

        request.httpMethod = "POST"
        request.addValue("Keep-Alive", forHTTPHeaderField: "Connection")
        request.addValue(tinode.userAgent, forHTTPHeaderField: "User-Agent")
        request.addValue("multipart/form-data; boundary=\(LargeFileHelper.kBoundary)", forHTTPHeaderField: "Content-Type")

        LargeFileHelper.addCommonHeaders(to: &request, using: self.tinode)

        var newData = Data()
        let header = LargeFileHelper.kTwoHyphens + LargeFileHelper.kBoundary + LargeFileHelper.kLineEnd +
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"" + LargeFileHelper.kLineEnd +
            "Content-Type: \(mimetype)" + LargeFileHelper.kLineEnd +
            "Content-Transfer-Encoding: binary" + LargeFileHelper.kLineEnd + LargeFileHelper.kLineEnd
        newData.append(contentsOf: header.utf8)
        newData.append(d)
        let footer = LargeFileHelper.kLineEnd + LargeFileHelper.kTwoHyphens + LargeFileHelper.kBoundary + LargeFileHelper.kTwoHyphens + LargeFileHelper.kLineEnd
        newData.append(contentsOf: footer.utf8)

        let tempDir = FileManager.default.temporaryDirectory

        let localFileName = UUID().uuidString
        let localURL = tempDir.appendingPathComponent("throwaway-\(localFileName)")
        try? newData.write(to: localURL)

        let uploadKey = LargeFileHelper.createUploadKey(topicId: topicId, msgId: msgId)
        upload.task = urlSession.uploadTask(with: request, fromFile: localURL)
        upload.task!.taskDescription = uploadKey
        upload.isUploading = true
        upload.topicId = topicId
        upload.msgId = msgId
        upload.progressCb = progressCallback
        upload.finalCb = completionCallback
        activeUploads[uploadKey] = upload
        upload.task!.resume()
    }

    public func cancelUpload(topicId: String, msgId: Int64) -> Bool {
        let uploadKey = LargeFileHelper.createUploadKey(topicId: topicId, msgId: msgId)
        var upload = activeUploads[uploadKey]
        guard upload != nil else { return false }
        activeUploads.removeValue(forKey: uploadKey)
        upload!.task?.cancel()
        upload = nil
        return true
    }

    public func startDownload(from url: URL) {
        var request = URLRequest(url: url)
        LargeFileHelper.addCommonHeaders(to: &request, using: self.tinode)

        let task = urlSession.downloadTask(with: request)
        task.resume()
    }

    public func getActiveUpload(for taskId: String) -> Upload? {
        return self.activeUploads[taskId]
    }
}

extension LargeFileHelper: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive: Data) {
        if let taskId = dataTask.taskDescription, let upload = self.getActiveUpload(for: taskId) {
            upload.appendResponse(didReceive)
        }
    }
}

extension LargeFileHelper: URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError: Error?) {
        guard let taskId = task.taskDescription, let upload = self.getActiveUpload(for: taskId) else {
            return
        }
        activeUploads.removeValue(forKey: taskId)
        var serverMsg: ServerMessage? = nil
        var uploadError: Error? = didCompleteWithError
        defer {
            upload.finalCb?(serverMsg, uploadError)
            upload.finalCb = nil
        }
        guard uploadError == nil else {
            return
        }
        Tinode.log.debug("LargeFileHelper - finished task: id = %@, topicId = %@", taskId, upload.topicId)
        guard let response = task.response as? HTTPURLResponse else {
            uploadError = TinodeError.invalidState(String(format: NSLocalizedString("Upload failed (%@). No server response.", comment: "Error message"), upload.topicId))
            return
        }
        guard response.statusCode == 200 else {
            uploadError = TinodeError.invalidState(String(format: NSLocalizedString("Upload failed (%@): response code %d.", comment: "Error message"), upload.topicId, response.statusCode))
            return
        }
        guard !upload.responseData.isEmpty else {
            uploadError = TinodeError.invalidState(String(format: NSLocalizedString("Upload failed (%@): empty response body.", comment: "Error message"), upload.topicId))
            return
        }
        do {
            serverMsg = try Tinode.jsonDecoder.decode(ServerMessage.self, from: upload.responseData)
        } catch {
            uploadError = error
            return
        }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if let taskId = task.taskDescription, let upload = self.getActiveUpload(for: taskId) {
            let progress: Float = totalBytesExpectedToSend > 0 ?
                Float(totalBytesSent) / Float(totalBytesExpectedToSend) : 0
            upload.progressCb?(progress)
        }
    }
}

