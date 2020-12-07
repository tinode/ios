//
//  ProgressView.swift
//  Tinodios
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import UIKit

class ProgressView : UIView {

    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var cancelButton: UIButton!

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
    }
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        loadNib()
    }

    private func loadNib() {
        Bundle.main.loadNibNamed("ProgressView", owner: self, options: nil)
        addSubview(containerView)
        containerView.frame = self.bounds
        containerView.autoresizingMask = [.flexibleWidth]
    }

    @IBAction func cancelProgress(_ sender: Any) {
    }

    public func setProgress(_ progress: Float) {
        progressView.setProgress(progress, animated: true)
    }
}
