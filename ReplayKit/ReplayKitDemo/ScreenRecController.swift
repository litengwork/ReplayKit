//
//  ScreenRecController.swift
//  ReplayKit
//
//  Created by ri on 2020/03/02.
//  Copyright © 2020 Lee. All rights reserved.
//

import UIKit
import Foundation
import AVFoundation
import Photos

public enum ScreenRecError: String {
    case paramError = "paramError"
    case recStartError = "recStartError"
    case recEndError = "recEndError"
    case exportError = "exportError"
    case concatError = "concatError"
    case saveError = "saveError"
    case timeoutError = "timeoutError"
}

protocol ScreenRecControllerDelegate: class {
    func onRecStart()
    func onRecPause()
    func onRecComplete()
    func onRecFail(with error: ScreenRecError)
    func onUpdateRecTime(with sec: Int)
}

public class RecordingParam {
    var filePath: String? = nil
    var createDatetime: Int64 = 0
}


class ScreenRecController: NSObject {
    private let THUMBNAIL_DURATION = 1000
    private let THUMBNAIL_SCALE = 0.5

    private var videoRecorderStartTime = Int64(0)
    private var audioRecorderStartTime = Int64(0)

    private let LESSON_VIDEO_EXPORT_DIRECTORY = "record/"
    private let sLessonDir = "video"
    private let file_separator = "/"
    private let sTemp = "_temp"

    private weak var mListener: ScreenRecControllerDelegate?
    private var mRecordingParam: RecordingParam?

    private var recordTimer: DispatchSourceTimer? = nil
    private var mElapsedTime: Int = 0
    private var mUserName: String! = ""
    private var mSwingId: String = ""

    private var recorder: ScreenRecorder!
    private var isRecording = false
    fileprivate var videoIndex = 0
    fileprivate var videoPaths = [URL]()
    fileprivate var timeout: Double = 300.0

    override init() {
        super.init()
        recorder = ScreenRecorder()
    }

    public func setEventListener(_ listener: ScreenRecControllerDelegate?) {
        mListener = listener
    }

    public func _release() {
        cancelTimer()
        clearTempVideo()
    }

    /// マイク使用許可チェック
    ///
    /// - Returns: マイク使用権限があったらtrueを返す
    public func getScreenRecordingPermission(completion: @escaping (_ success: Bool)-> Void) {
        let status: AVAudioSession.RecordPermission = AVAudioSession.sharedInstance().recordPermission
        switch status {
        case AVAudioSession.RecordPermission.undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission({ (granted) in
                if granted {
                    completion(true)
                } else {
                    completion(false)
                }
            })
        case AVAudioSession.RecordPermission.denied:
            completion(false)

        case AVAudioSession.RecordPermission.granted:
            completion(true)

        default:
            completion(false)

        }
    }

    /// スクリーンレコード開始
    public func start() {
        print("record start")
        if isRecording {
            return
        }
        videoIndex = 0
        let param: RecordingParam = RecordingParam()
        param.createDatetime = Date().dateToInt()
        param.filePath = getCacheDir() + String(param.createDatetime) + ".mp4"
        mRecordingParam = param

        DispatchQueue.main.async {
            if let rec = self.recorder {
                rec.startRec { (error) in
                    self.isRecording = true
                    if let _ = error, let listener = self.mListener {
                        listener.onRecFail(with: .recStartError)
                        // 収録開始失敗の場合
                        self.isRecording = false
                        rec.stopRec { (_, _) in

                        }
                    } else {
                        // Start Timer
                        self.startTimer()
                        // Start Record
                        self.mListener?.onRecStart()
                    }
                }
            }
        }
    }

    /// レコード一時停止
    public func pause() {
        print("record pause")
        if !isRecording {
            return
        }
        // Pause Timer
        pauseTimer()
        // Record 一時停止
        if let rec = self.recorder {
            rec.stopRec { (rppv, error) in
                self.isRecording = false
                if let _ = error, let listener = self.mListener {
                    // 収録削除
                    rec.discardRec()
                    listener.onRecFail(with: .recEndError)
                } else {
                    // VideoFile Export処理
                    if let movieUrl: URL = rppv?.value(forKey: "movieURL") as? URL {
                        self.export(with: movieUrl.path) { (error, filepath) in
                            if error == nil {
                                // Export成功の場合
                                self.videoPaths.append(URL(fileURLWithPath: filepath ?? ""))
                                self.videoIndex += 1
                                self.mListener?.onRecPause()
                            } else {
                                // Export失敗の場合
                                // TmpFile 削除する
                                self.clearTempVideo(filepath)
                                self.mListener?.onRecFail(with: error ?? .exportError)
                            }
                        }
                    } else {
                        self.mListener?.onRecFail(with: .recEndError)
                    }
                }
            }
        }
    }
    /// レコード再開
    public func resume() {
        print("record resume")
        if isRecording {
            return
        }
        // Resume Timer
        resumeTimer()
        // Record　再開する
        if let rec = self.recorder {
            rec.startRec { (error) in
                self.isRecording = true
                if let _ = error, let listener = self.mListener {
                    listener.onRecFail(with: .recStartError)
                    // 再開失敗の場合
                    self.isRecording = false
                    rec.stopRec { (_, _) in }
                }
            }
        }
    }
    /// レコード停止
    public func stop() {
        print("record stop")
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.queue.concat", qos: .default, attributes: .concurrent)
        queue.async(group: group, qos: .default, flags: [], execute: {
            // Record 終了
            self.concat { (error, filepath) in
                if let err = error {
                    // concat失敗の場合
                    // TmpFile 削除する
                    self.clearTempVideo(filepath)
                    self.mListener?.onRecFail(with: err)
                } else {
                    if let fileP = filepath {
                        // 保存
                        self.save(with: fileP) { (error) in
                            if let err = error {
                                // TmpFile 削除する
                                self.clearTempVideo(fileP)
                                self.mListener?.onRecFail(with: err)
                            } else {
                                // すべてSuccess
                                self.mListener?.onRecComplete()
                            }
                        }
                    }
                }
            }
        })

        let result = group.wait(timeout: .now() + timeout)
        if result == .timedOut {
            print("Time Out")
            self.mListener?.onRecFail(with: .timeoutError)
        }
    }
    /// レコード停止そしてバックグラウンドに移行
    public func stopWithBackground() {
        print("record stop With Background")
        if !isRecording {
            return
        }
        // Pause Timer
        pauseTimer()
        // Record Background 停止
        if let rec = self.recorder {
            rec.stopRec { (rppv, error) in
                self.isRecording = false
                if let _ = error, let listener = self.mListener {
                    // 収録削除
                    rec.discardRec()
                    listener.onRecFail(with: .recEndError)
                } else {
                    // VideoFile Export処理
                    if let movieUrl: URL = rppv?.value(forKey: "movieURL") as? URL {
                        self.export(with: movieUrl.path) { (error, filepath) in
                            if error == nil {
                                // Export成功の場合
                                self.videoPaths.append(URL(fileURLWithPath: filepath ?? ""))
                                self.videoIndex += 1
                                self.stop()
                            } else {
                                // Export失敗の場合
                                // TmpFile 削除する
                                self.clearTempVideo(filepath)
                                self.mListener?.onRecFail(with: error ?? .exportError)
                            }
                        }
                    } else {
                        self.mListener?.onRecFail(with: .recEndError)
                    }
                }
            }
        }
    }
}

extension ScreenRecController {
    // ① Export
    fileprivate func export(with filePath: String, complete: ((_ error: ScreenRecError?, _ filePath: String?) -> Void)? = nil) {
        print("record export tmp video")
        do {
            let exportPath: String = getCacheDir() + "\(Date().dateToInt())" + sTemp + "(\(videoIndex)).mp4"
            let fileUrl = URL(fileURLWithPath: filePath)
            let fileAsset = AVURLAsset(url: fileUrl)

            // コンポジションを作成する
            let mixComposition = AVMutableComposition()

            guard fileAsset.tracks(withMediaType: .video).count > 0 && fileAsset.tracks(withMediaType: .audio).count > 0  else {
                complete?(.exportError, filePath)
                return
            }
            //作成されたオーディオファイルと動画ファイル
            for mAVAssetTrack in fileAsset.tracks {
                if mAVAssetTrack.mediaType == .audio {
                    let track = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    try track?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: fileAsset.duration), of: mAVAssetTrack, at: .zero)
                } else if mAVAssetTrack.mediaType == .video {
                    let track = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                    try track?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: fileAsset.duration), of: mAVAssetTrack, at: .zero)
                }
            }

            // 出力ファイル設定(ファイルが存在している場合は削除)
            let assetExport: AVAssetExportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPreset1280x720)!

            if FileManager.default.fileExists(atPath: exportPath) {
                try FileManager.default.removeItem(atPath: exportPath)
            }

            // エクスポートセッションを作成
            assetExport.outputFileType = .mp4
            assetExport.outputURL = URL(fileURLWithPath: exportPath)
            assetExport.shouldOptimizeForNetworkUse = false

            assetExport.exportAsynchronously {
                if assetExport.status == AVAssetExportSession.Status.completed {
                    print("Record SaveTmpVideo Success")
                    complete?(nil, exportPath)
                } else {
                    complete?(.exportError, exportPath)
                    print("\(#function) fail \(assetExport.status) \(String(describing: assetExport.error.debugDescription))")
                }
            }
        } catch let e as NSError {
            print("\(#function) fail \(e) \(e.localizedDescription)")
            complete?(.exportError, filePath)
            return
        }
    }

    // ② concat
    fileprivate func concat(complete: ((_ error: ScreenRecError?, _ filePath: String?) -> Void)? = nil) {
        print("record video concat")
        do {
            if videoPaths.isEmpty {
                complete?(.concatError, nil)
            }
            let mixComposition = AVMutableComposition()
            let audioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            let videoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            var totalDuration = CMTime.zero

            for fileUrl in videoPaths {
                let fileAsset = AVURLAsset(url: fileUrl)
                if fileAsset.tracks(withMediaType: .video).count > 0 && fileAsset.tracks(withMediaType: .audio).count > 0 {

                    for mAVAssetTrack in fileAsset.tracks {
                        if mAVAssetTrack.mediaType == .audio {
                            try audioTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: fileAsset.duration), of: mAVAssetTrack, at: totalDuration)
                        } else if mAVAssetTrack.mediaType == .video {
                            try videoTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: fileAsset.duration), of: mAVAssetTrack, at: totalDuration)
                        }
                    }

                    totalDuration = CMTimeAdd(totalDuration, fileAsset.duration)
                }
            }

            // 出力ファイル設定(ファイルが存在している場合は削除)
            let assetExport: AVAssetExportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPreset1280x720)!
            guard let exportPath = self.mRecordingParam?.filePath else {
                complete?(.concatError, self.mRecordingParam?.filePath)
                return
            }
            if FileManager.default.fileExists(atPath: exportPath) {
                try FileManager.default.removeItem(atPath: exportPath)
            }
            // エクスポートセッションを作成
            assetExport.outputFileType = .mp4
            assetExport.outputURL = URL(fileURLWithPath: exportPath)
            assetExport.shouldOptimizeForNetworkUse = false
            assetExport.exportAsynchronously(completionHandler: {

                DispatchQueue.main.async {
                    if assetExport.status == AVAssetExportSession.Status.completed {
                        print("Record Concat Success")
                        complete?(nil, exportPath)
                    } else {
                        print("\(#function) fail \(assetExport.status) \(String(describing: assetExport.error.debugDescription))")
                        complete?(.concatError, exportPath)
                    }
                }
            })
        } catch let e as NSError {
            print("\(#function) fail \(e) \(e.localizedDescription)")
            complete?(.concatError, nil)
            return
        }
    }

    // ③ save
    fileprivate func save(with exportFilePath: String, complete: ((_ error: ScreenRecError?) -> Void)? = nil) {
        if let thumbnail = self.createThumbnail(filePath: exportFilePath), let img = UIImage(data: thumbnail) {
            UIImageWriteToSavedPhotosAlbum(img, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
            UISaveVideoAtPathToSavedPhotosAlbum(exportFilePath, self, #selector(video(_:didFinishSavingWithError:contextInfo:)), nil)
            complete?(nil)
        }
    }
    // mergedidFinish
    private func mergedidFinish(videoPath: String, datapath: String) {
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: videoPath) {
                let dataDirectory = NSHomeDirectory() + "/Library/" + LESSON_VIDEO_EXPORT_DIRECTORY
                var isDir: ObjCBool = ObjCBool(false)
                if fileManager.fileExists(atPath: dataDirectory, isDirectory: &isDir) {
                    if !isDir.boolValue {
                        try fileManager.createDirectory(atPath: dataDirectory, withIntermediateDirectories: false, attributes: nil)
                    }
                } else {
                    try fileManager.createDirectory(atPath: dataDirectory, withIntermediateDirectories: false, attributes: nil)
                }

                try fileManager.moveItem(atPath: videoPath, toPath: datapath)
            } else {
                self.mListener?.onRecFail(with: .saveError)
            }

        } catch let error as NSError {
            print("Could not delete old recording file at path:\(error)")
            self.mListener?.onRecFail(with: .saveError)
        }
    }

    // createThumbnail
    private func createThumbnail(filePath: String) -> Data? {
        if let bitmap = VideoThumbnailUtils.createVideoThumbnail(filePath: filePath,
                                                                 thumbnailDuration: THUMBNAIL_DURATION,
                                                                 scaleRate: Float(THUMBNAIL_SCALE)) {
            let uiImage = UIImage(cgImage: bitmap)
            let data: Data? = uiImage.pngData()
            return data
        } else {
            return nil
        }
    }

    // clearTempVideo
    fileprivate func clearTempVideo(_ filePath: String? = nil) {
        let fileManager = FileManager.default
        if let fileP = filePath {
            if fileManager.fileExists(atPath: fileP) {
                do {
                    try fileManager.removeItem(atPath: fileP)
                } catch let error as NSError {
                    print("Could not delete old recording file at path:\(error)")
                }
            }
        } else {
            for fileUrl in videoPaths {
                if fileManager.fileExists(atPath: fileUrl.path) {
                    do {
                        try fileManager.removeItem(atPath: fileUrl.path)
                    } catch let error as NSError {
                        print("Could not delete old recording file at path:\(error)")
                    }
                }
            }
            self.videoPaths.removeAll()
            self.videoIndex = 0
        }
    }

    // getCacheDir
    private func getCacheDir() -> String {

        let cachePath = NSHomeDirectory() + "/Library/Caches/"
        let path = cachePath + sLessonDir + file_separator

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            return path
        }
        do {
            try fileManager.createDirectory(atPath: path,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
            return path
        } catch {
            print(error.localizedDescription)
            return cachePath
        }
    }
}

extension ScreenRecController {
    // RecordTimer
    fileprivate func startTimer() {
        if recordTimer == nil {
            recordTimer = DispatchSource.makeTimerSource(flags: [], queue: .main)
            recordTimer?.activate()
            recordTimer?.schedule(wallDeadline: .now(), repeating: .seconds(1), leeway: .seconds(0))
            recordTimer?.setEventHandler {
                if let listener = self.mListener {
                    listener.onUpdateRecTime(with: self.mElapsedTime)
                    self.mElapsedTime+=1
                }
            }
        }
    }

    fileprivate func pauseTimer() {
        if let rTimer = recordTimer {
            rTimer.suspend()
        }
    }

    fileprivate func resumeTimer() {
        if let rTimer = recordTimer {
            rTimer.resume()
        }
    }

    fileprivate func cancelTimer() {
        if let rTimer = recordTimer {
            rTimer.resume()
            rTimer.cancel()
            recordTimer = nil
            self.mElapsedTime = 0
        }
    }
}

extension ScreenRecController {
    @objc fileprivate func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if (error != nil) {
            print("写真の保存に失敗しました。")
        } else {
            print("写真の保存に成功しました。")
        }


    }
    
    @objc fileprivate func video(_ videoPath: String, didFinishSavingWithError error: NSError!, contextInfo: UnsafeMutableRawPointer) {
        if (error != nil) {
            print("動画の保存に失敗しました。")
        } else {
            print("動画の保存に成功しました。")
        }
    }
}

extension Date {
    public func dateToInt() -> Int64 {
        return Int64(self.timeIntervalSince1970 * 1000)
    }
}
