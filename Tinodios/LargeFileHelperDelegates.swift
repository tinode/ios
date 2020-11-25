//
//  LargeFileHelperDelegates.swift
//  Tinodios
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

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

// Downloads.
extension LargeFileHelper: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard downloadTask.error == nil else {
            Cache.log.error("LargeFileHelper - download failed: %@", downloadTask.error!.localizedDescription)
            return
        }

        guard let url = downloadTask.originalRequest?.url else { return }
        let fn = url.extractQueryParam(withName: "origfn") ?? url.lastPathComponent

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
