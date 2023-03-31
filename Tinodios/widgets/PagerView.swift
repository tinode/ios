//
//  ViewPager.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//


import UIKit

public protocol PagerViewDelegate: AnyObject {
    func didSelectPage(index: Int)
}

@IBDesignable
public class PagerView: UIView, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {

    // MARK: - Initialization
    init(pages: [UIView] = []) {
        self.pages = pages
        super.init(frame: .zero)

        // Make right-side corners round.
        self.layer.cornerRadius = 20
        self.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]

        self.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(collectionView)
        collectionView.backgroundColor = .systemBackground

        NSLayoutConstraint.activate([
            collectionView.widthAnchor.constraint(equalTo: self.widthAnchor),
            collectionView.heightAnchor.constraint(equalTo: self.heightAnchor),
            collectionView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            collectionView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Properties
    public weak var delegate: PagerViewDelegate?
    public var pages: [UIView] {
        didSet {
            self.collectionView.reloadData()
        }
    }

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.isPagingEnabled = true
        collectionView.register(PagerViewCell.self, forCellWithReuseIdentifier: "PagerViewCell")
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.translatesAutoresizingMaskIntoConstraints =  false
        return collectionView
    }()

    // MARK: - Data Source
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return pages.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "PagerViewCell", for: indexPath) as! PagerViewCell
        let page = self.pages[indexPath.item]
        cell.view = page
        return cell
    }

    // MARK: - Actions
    public func moveToPage(at index: Int) {
        self.collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: true)
    }

    // MARK: - Delegate
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(self.collectionView.contentOffset.x / self.collectionView.frame.size.width)

        self.delegate?.didSelectPage(index: page)
    }

    // MARK: - Layout Delegate
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {

        return CGSize(width: self.collectionView.frame.width,
                      height: self.collectionView.frame.height)
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }
}
