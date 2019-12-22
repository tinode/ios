//
//  CircularProgressView.swift
//  Tinodios
//

//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

// Circular progress indicator (like UIProgressBar).
class CircularProgressView: UIView {
    static private let kLineWidth: CGFloat = 3.0

    var stopButton: UIButton = {
        let button = UIButton()
        button.backgroundColor = .blue
        return button
    }()

    private var progressLayer = CAShapeLayer()
    private var trackLayer = CAShapeLayer()

    private var progressColor = UIColor.blue {
        didSet {
            progressLayer.strokeColor = progressColor.cgColor
        }
    }

    private var trackColor = UIColor.white {
        didSet {
            trackLayer.strokeColor = trackColor.cgColor
        }
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(stopButton)
        bringSubviewToFront(stopButton)
        updateLayout()
    }

    convenience public init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var frame: CGRect {
        didSet {
            updateLayout()
        }
    }

    private func updateLayout() {
        let size = self.frame.size
        // Make progress tracks.
        self.layer.cornerRadius = size.width / 2
        let circlePath = UIBezierPath(
            arcCenter: CGPoint(x: size.width / 2, y: size.height / 2),
            radius: (size.width - 1.5) / 2,
            startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: true)
        trackLayer.path = circlePath.cgPath
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = trackColor.cgColor
        trackLayer.lineWidth = CircularProgressView.kLineWidth
        trackLayer.strokeEnd = 1.0
        layer.addSublayer(trackLayer)
        progressLayer.path = circlePath.cgPath
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = progressColor.cgColor
        progressLayer.lineWidth = CircularProgressView.kLineWidth
        progressLayer.strokeEnd = 0.0
        layer.addSublayer(progressLayer)

        // Place stopButton at the center of the view.
        let btnSize = CGSize(width: size.width / 2, height: size.height / 2)
        let btnOrigin = CGPoint(x: size.width / 4, y: size.height / 4)
        let btnFrame = CGRect(origin: btnOrigin, size: btnSize)
        stopButton.frame = btnFrame
    }

    public func setProgress(value: Float, withAnimation animated: Bool) {
        guard Float(0.0) <= value && value <= Float(1.0) else { return }
        var animation: CABasicAnimation? = nil
        if animated {
            animation = CABasicAnimation(keyPath: "strokeEnd")
            animation!.duration = 0.3
            animation!.fromValue = progressLayer.strokeEnd
            animation!.toValue = value
            animation!.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
        }
        progressLayer.strokeEnd = CGFloat(value)
        if animation != nil {
            progressLayer.add(animation!, forKey: "animationProgress")
        }
    }
}
