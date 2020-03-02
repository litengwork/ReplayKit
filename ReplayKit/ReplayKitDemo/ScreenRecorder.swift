//
//  ScreenRecorder.swift
//  ReplayKit
//
//  Created by ri on 2020/03/02.
//  Copyright © 2020 Lee. All rights reserved.
//

import UIKit
import ReplayKit

class ScreenRecorder: NSObject {
    private var recorder: RPScreenRecorder!

    override init() {
        super.init()
        recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = true
    }

    public func startRec(completion: @escaping(Error?) -> Void) {
        if let rec = recorder {
            rec.startRecording { (error) in
                completion(error)
            }
        }
    }

    public func stopRec(completion: @escaping(RPPreviewViewController?, Error?) -> Void) {
        if let rec = recorder {
            rec.stopRecording { (rppv, error) in
                completion(rppv, error)
            }
        }
    }

    public func discardRec(completion: (() -> Void)? = nil) {
        if let rec = recorder {
            rec.discardRecording {
                completion?()
            }
        }
    }
}
