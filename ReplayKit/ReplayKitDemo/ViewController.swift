//
//  ViewController.swift
//  ReplayKit
//
//  Created by ri on 2020/03/02.
//  Copyright © 2020 Lee. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation

class ViewController: UIViewController {

    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var startBtn: UIButton!
    @IBOutlet weak var activty: UIActivityIndicatorView!

    fileprivate var mScreenRecController: ScreenRecController!

    fileprivate var isRec: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        mScreenRecController = ScreenRecController()
        mScreenRecController.setEventListener(self)
        activty.stopAnimating()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self,
                                       selector: #selector(self.viewWillEnterForeground(_:)),
                                       name: UIApplication.willEnterForegroundNotification,
                                       object: nil)
        notificationCenter.addObserver(self,
                                       selector: #selector(self.viewDidEnterBackground(_:)),
                                       name: UIApplication.didEnterBackgroundNotification,
                                       object: nil)
    }
}

extension ViewController {

    @objc func viewWillEnterForeground(_ notification: Notification?) {
        timeLabel.text = ""
    }

    @objc func viewDidEnterBackground(_ notification: Notification?) {
        if isRec {
            if let alertcontroller = self.presentedViewController as? UIAlertController, alertcontroller.message == "終了しますか？" {
                alertcontroller.dismiss(animated: false, completion: nil)
                mScreenRecController.stop()
            } else {
                mScreenRecController.stopWithBackground()
            }
        }
    }

    @IBAction func startBtnAction(_ sender: UIButton) {
        if isRec {
            activty.startAnimating()
            mScreenRecController.pause()
        } else {
            mScreenRecController.getScreenRecordingPermission { (isSuccess) in
                if isSuccess {
                    self.mScreenRecController.start()
                }
            }
        }
    }
}

extension ViewController: ScreenRecControllerDelegate {
    func onRecPause() {
        DispatchQueue.main.async {
            self.activty.stopAnimating()
            self.showAlert(title: "終了しますか？", ishowcancel: true, confirm: {
                self.activty.startAnimating()
                self.mScreenRecController.stop()
            }) {
                self.mScreenRecController.resume()
            }
        }
    }

    func onRecStart() {
        DispatchQueue.main.async {
            self.isRec = true
            self.startBtn.setTitle("Pause", for: .normal)
        }
    }

    func onRecComplete() {
        DispatchQueue.main.async {
            self.activty.stopAnimating()
            self.isRec = false
            self.startBtn.setTitle("START", for: .normal)
            self.timeLabel.text = "Complete"
            self.mScreenRecController._release()
            self.showAlert(title: "Complete")
        }
    }

    func onRecFail(with error: ScreenRecError) {
        DispatchQueue.main.async {
            self.activty.stopAnimating()
            self.isRec = false
            self.startBtn.setTitle("START", for: .normal)
            self.timeLabel.text = error.rawValue
            self.mScreenRecController._release()
            self.showAlert(title: error.rawValue)
        }
    }

    func onUpdateRecTime(with sec: Int) {
        DispatchQueue.main.async {
            self.timeLabel.text = sec.formatSecStr()
        }
    }
}

extension UIViewController {
    func showAlert(title: String = "", ishowcancel: Bool = false, confirm: (() -> Void)? = nil, cancel: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let action = UIAlertAction(title: "OK", style: .default) { _ in
            confirm?()
        }
        alert.addAction(action)
        if ishowcancel {
            let action1 = UIAlertAction(title: "Cancel", style: .destructive) { _ in
                cancel?()
            }
            alert.addAction(action1)
        }
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }
}

extension Int {
    func formatSecStr() -> String {
        let seconds = self % 60
        let minutes = (self / 60) % 60
        let hours = (self / 60 / 60) % 60
        return NSString.init(format: "%02d : %02d : %02d", hours, minutes, seconds) as String
    }
}
