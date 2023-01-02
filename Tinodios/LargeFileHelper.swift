//
//  LargeFileHelper.swift
//
//  Copyright © 2020-2022 Tinode LLC. All rights reserved.
//

import TinodeSDK

public class Upload {
    fileprivate var url: URL
    fileprivate var topicId: String = ""
    fileprivate var msgId: Int64 = 0
    fileprivate var filename: String = ""
    fileprivate var isUploading = false
    fileprivate var progress: Float = 0
    fileprivate var responseData: Data = Data()
    fileprivate var progressCb: ((Float) -> Void)?
    fileprivate var finalCb: ((ServerMessage?, Error?) -> Void)?

    fileprivate var task: URLSessionUploadTask?

    public var id: String {
        return "\(topicId)-\(msgId)-\(filename)"
    }

    public var hasResponse: Bool {
        return !self.responseData.isEmpty
    }

    init(url: URL) {
        self.url = url
    }

    deinit {
        if let cb = finalCb {
            cb(nil, TinodeError.invalidState("Topic \(topicId), msg id \(msgId), filename \(filename): Could not finish upload. Cancelling."))
        }
    }

    public func appendResponse(_ other: Data) {
        self.responseData.append(other)
    }

    public func getResponse() -> Data {
        return self.responseData
    }

    public func progress(_ val: Float) {
        self.progressCb?(val)
    }

    public func finished(msg: ServerMessage?, err: Error?) {
        self.finalCb?(msg, err)
        self.finalCb = nil
    }
}

public class LargeFileHelper: NSObject {
    static let kBoundary = "*****\(Date().millisecondsSince1970)*****"
    static let kTwoHyphens = "--"
    static let kLineEnd = "\r\n"

    private var urlSession: URLSession!
    private var activeUploads: [String: Upload] = [:]
    private var tinode: Tinode!

    init(with tinode: Tinode, config: URLSessionConfiguration) {
        super.init()
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.tinode = tinode
    }

    convenience init(with tinode: Tinode) {
        let config = URLSessionConfiguration.background(withIdentifier: Bundle.main.bundleIdentifier!)
        self.init(with: tinode, config: config)
    }

    public static func addCommonHeaders(to request: inout URLRequest, using tinode: Tinode) {
        let headers = tinode.getRequestHeaders()
        headers.forEach({ (key: String, value: String) in
            request.addValue(value, forHTTPHeaderField: key)
        })
    }

    public static func addAuthQueryParams(to url: URL, using tinode: Tinode) -> URL {
        return tinode.addAuthQueryParams(url)
    }

    public static func taskID(forTopic topicId: String, msgId: Int64, filename: String) -> String {
        if msgId != 0 {
            return "\(topicId)-\(msgId)-\(filename)"
        }
        return "\(topicId)-avatar"
    }

    public func startMsgAttachmentUpload(filename: String, mimetype: String, data payload: Data, topicId: String, msgId: Int64, progressCallback: ((Float) -> Void)?, completionCallback: @escaping (ServerMessage?, Error?) -> Void) {
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
        let header = LargeFileHelper.kTwoHyphens + LargeFileHelper.kBoundary + LargeFileHelper.kLineEnd + "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"" + LargeFileHelper.kLineEnd + "Content-Type: \(mimetype)" + LargeFileHelper.kLineEnd + "Content-Transfer-Encoding: binary" + LargeFileHelper.kLineEnd + LargeFileHelper.kLineEnd
        newData.append(contentsOf: header.utf8)
        newData.append(payload)
        let footer = LargeFileHelper.kLineEnd + LargeFileHelper.kTwoHyphens + LargeFileHelper.kBoundary + LargeFileHelper.kTwoHyphens + LargeFileHelper.kLineEnd
        newData.append(contentsOf: footer.utf8)

        let tempDir = FileManager.default.temporaryDirectory

        let localFileName = UUID().uuidString
        let localURL = tempDir.appendingPathComponent("throwaway-\(localFileName)")
        try? newData.write(to: localURL)

        let uploadKey = LargeFileHelper.taskID(forTopic: topicId, msgId: msgId, filename: filename)
        upload.task = urlSession.uploadTask(with: request, fromFile: localURL)
        upload.task!.taskDescription = uploadKey
        upload.isUploading = true
        upload.topicId = topicId
        upload.msgId = msgId
        upload.filename = filename
        upload.progressCb = progressCallback
        upload.finalCb = completionCallback
        activeUploads[uploadKey] = upload
        upload.task!.resume()
    }

    public func startAvatarUpload(mimetype: String, data payload: Data, topicId: String, completionCallback: @escaping (ServerMessage?, Error?) -> Void) {
        let fileName = "avatar-\(Utils.uniqueFilename(forMime: mimetype))"
        startMsgAttachmentUpload(filename: fileName, mimetype: mimetype, data: payload, topicId: topicId, msgId: 0, progressCallback: {_ in /* do nothing */}, completionCallback: completionCallback)
    }

    public func cancelUpload(topicId: String, msgId: Int64 = 0) -> Bool {
        let uploadKeyPrefix = LargeFileHelper.taskID(forTopic: topicId, msgId: msgId, filename: "")
        var keys = [String]()
        for uploadKey in activeUploads.keys {
            if uploadKey.starts(with: uploadKeyPrefix) {
                keys.append(uploadKey)
            }
        }
        for k in keys {
            if let upload = activeUploads.removeValue(forKey: k) {
                upload.task?.cancel()
            }
        }
        return !keys.isEmpty
    }

    public func getActiveUpload(for taskId: String) -> Upload? {
        return self.activeUploads[taskId]
    }

    public func uploadFinished(for taskId: String) {
        self.activeUploads.removeValue(forKey: taskId)
    }

    public func startDownload(from url: URL) {
        var request = URLRequest(url: url)
        LargeFileHelper.addCommonHeaders(to: &request, using: self.tinode)

        let task = urlSession.downloadTask(with: request)
        task.resume()
    }
}

extension LargeFileHelper: URLSessionDelegate {
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
                let completionHandler = appDelegate.backgroundSessionCompletionHandler {
                appDelegate.backgroundSessionCompletionHandler = nil
                completionHandler()
            }
        }
    }
}

// Upload result
extension LargeFileHelper: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive: Data) {
        if let taskId = dataTask.taskDescription, let upload = self.getActiveUpload(for: taskId) {
            upload.appendResponse(didReceive)
        }
    }
}

// Upload progress
extension LargeFileHelper: URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError: Error?) {
        guard let taskId = task.taskDescription, let upload = self.getActiveUpload(for: taskId) else {
            return
        }
        self.uploadFinished(for: taskId)
        var serverMsg: ServerMessage?
        var uploadError: Error? = didCompleteWithError
        defer {
            upload.finished(msg: serverMsg, err: uploadError)
        }
        guard uploadError == nil else {
            return
        }
        guard let response = task.response as? HTTPURLResponse else {
            uploadError = TinodeError.invalidState(String(format: NSLocalizedString("Upload failed (%@). No server response.", comment: "Error message"), upload.id))
            return
        }
        guard response.statusCode == 200 else {
            uploadError = TinodeError.invalidState(String(format: NSLocalizedString("Upload failed (%@): response code %d.", comment: "Error message"), upload.id, response.statusCode))
            return
        }
        guard upload.hasResponse else {
            uploadError = TinodeError.invalidState(String(format: NSLocalizedString("Upload failed (%@): empty response body.", comment: "Error message"), upload.id))
            return
        }
        do {
            serverMsg = try Tinode.jsonDecoder.decode(ServerMessage.self, from: upload.getResponse())
        } catch {
            uploadError = error
            return
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if let taskId = task.taskDescription, let upload = self.getActiveUpload(for: taskId) {
            let progress: Float = totalBytesExpectedToSend > 0 ? Float(totalBytesSent) / Float(totalBytesExpectedToSend) : 0
            upload.progress(progress)
        }
    }
}

// Downloads.
extension LargeFileHelper: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard downloadTask.error == nil else {
            Cache.log.error("LargeFileHelper - download failed: %@", downloadTask.error!.localizedDescription)
            return
        }

        guard let url = downloadTask.originalRequest?.url else { return }
        let fn = url.extractQueryParam(named: "origfn") ?? url.lastPathComponent

        let documentsUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsUrl.appendingPathComponent(fn)

        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: destinationURL)
        } catch {
            // Non-fatal: file probably doesn't exist
        }
        do {
            try fileManager.moveItem(at: location, to: destinationURL)
            UiUtils.presentFileSharingVC(for: destinationURL)
        } catch {
            Cache.log.error("LargeFileHelper - could not copy file to disk: %@", error.localizedDescription)
        }
    }
}
