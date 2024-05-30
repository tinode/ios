//
//  PagerViewCell.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import UIKit

public class PagerViewCell: UICollectionViewCell {

    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)

        self.setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Properties
    public var view: UIView? {
        didSet {
            self.setup()
        }
    }

    // MARK: - UI Setup
    private func setup() {
        guard let view = view else { return }

        self.contentView.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: self.contentView.leftAnchor),
            view.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            view.rightAnchor.constraint(equalTo: self.contentView.rightAnchor),
            view.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor)
        ])
    }
}
