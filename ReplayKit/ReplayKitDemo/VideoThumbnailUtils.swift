//
//  VideoThumbnailUtils.swift
//  ReplayKitDemo
//
//  Created by ri on 2020/03/06.
//  Copyright © 2020 Lee. All rights reserved.
//

import UIKit
import AVFoundation

public class VideoThumbnailUtils: NSObject {

    public static func createVideoThumbnail(filePath: String, thumbnailDuration: Int, scaleRate: Float) -> CGImage? {

        let asset = AVAsset.init(url: URL.init(fileURLWithPath: filePath))
        var videoSize: CGSize?
        for track in asset.tracks {
            if track.mediaType == AVMediaType.video {
                videoSize = track.naturalSize
            }
        }
        let videoHeight = videoSize?.height ?? 0
        let videoWidth = videoSize?.width ?? 0
        var reSize: CGFloat = 0
        if videoHeight >= videoWidth {
           reSize = videoHeight * CGFloat(scaleRate)
        } else {
           reSize = videoWidth * CGFloat(scaleRate)
        }

        let assetImageGenerator = AVAssetImageGenerator(asset: asset)
        assetImageGenerator.appliesPreferredTrackTransform = true
        assetImageGenerator.maximumSize = CGSize(width: reSize, height: reSize)
        var time = asset.duration
        time.value = min(30, 32)
        var actualTime: CMTime = CMTimeMake(value: 1, timescale: 1)
        do {
            // CGImage
            let imageRef = try assetImageGenerator.copyCGImage(at: CMTimeMakeWithSeconds(0.0, preferredTimescale: 600), actualTime: &actualTime)
            return imageRef
        } catch let error as NSError {
            print("createVideoThumbnail filePath.\(filePath) error.\(error)")
            return nil
        }

    }

}
