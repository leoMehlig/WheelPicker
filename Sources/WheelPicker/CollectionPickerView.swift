import UIKit
import Combine

public protocol AccessibleValue {
    var accessibilityText: String { get }
}

class CollectionPickerView<Cell: UICollectionViewCell, Center: UIView, Value: Hashable>: UIView, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate {
    var values: [Value] = [] {
        didSet {
            if values != oldValue {
                self.reload()
            }
        }
    }

    private lazy var diffDataSource: UICollectionViewDiffableDataSource<Int, Value> = {
        let cellRegistration = UICollectionView.CellRegistration<Cell, Value> { cell, _, value in
            self.configureCell(cell, value)
        }
        let dataSource = UICollectionViewDiffableDataSource<Int, Value>(collectionView: self.collectionView) { collectionView, indexPath, id in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration,
                                                                for: indexPath,
                                                                item: id)
        }
        return dataSource
    }()

    private lazy var sizingCell: Cell = Cell()

    private let selectionFeedback = UISelectionFeedbackGenerator()

    public let publisher: CurrentValueSubject<Value, Never>

    private var selectedIndex: Int {
        didSet {
            if self.values.indices.contains(self.selectedIndex), oldValue != self.selectedIndex {
                self.publisher.send(values[self.selectedIndex])
                self.layout?.selected = values[self.selectedIndex]
                self.updateAccessibility()
            }
        }
    }

    let configureCell: (Cell, Value) -> Void

    var centerSize: Int  {
        get { self.layout?.centerSize ?? 1}
        set{ self.layout?.centerSize = newValue }
    }
  

    init(values: [Value],
         selected: Value,
         configureCell: @escaping (Cell, Value) -> Void,
         configureCenter: @escaping (Center, Value) -> Void) {
        self.configureCell = configureCell
        self.publisher = CurrentValueSubject(selected)
        self.selectedIndex = values.firstIndex(of: selected) ?? 0
        super.init(frame: .zero)

        self.backgroundColor = .clear

        let layout = Layout<Center, Value>(selected: selected, configureCenter: configureCenter)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView = cv
        cv.delegate = self
        cv.dataSource = self.diffDataSource
        cv.isScrollEnabled = true
        cv.showsHorizontalScrollIndicator = false
        cv.showsVerticalScrollIndicator = false
        cv.decelerationRate = UIScrollView.DecelerationRate.normal
        cv.backgroundColor = .clear
        cv.layer.sublayerTransform = {
            var transform = CATransform3DIdentity;
            transform.m34 = -1.0 / 2000;
            return transform;
        }()

        cv.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(cv)
        NSLayoutConstraint.activate([
            cv.topAnchor.constraint(equalTo: self.topAnchor, constant: 0),
            cv.leftAnchor.constraint(equalTo: self.leftAnchor, constant: 0),
            cv.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0),
            cv.rightAnchor.constraint(equalTo: self.rightAnchor, constant: 0),
        ])

        self.values = values

        self.reload()

        self.isAccessibilityElement = true
        self.accessibilityTraits.insert(UIAccessibilityTraits.adjustable)
        self.updateAccessibility()
    }

    override func accessibilityIncrement() {
        let new = self.selectedIndex + 1
        if self.values.indices.contains(new) {
            self.scrollToItem(at: new)
            self.selectionFeedback.selectionChanged()
        }
    }

    override func accessibilityDecrement() {
        let new = self.selectedIndex - 1
        if self.values.indices.contains(new) {
            self.scrollToItem(at: new)
            self.selectionFeedback.selectionChanged()
        }
    }

    private func updateAccessibility() {
        let value = self.values[self.selectedIndex]
        self.accessibilityValue = (value as? AccessibleValue)?.accessibilityText ?? (value as? CustomStringConvertible)?.description
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.layer.mask = {
            let maskLayer = CAGradientLayer()
            maskLayer.frame = self.bounds
            maskLayer.colors = [
                UIColor.clear.cgColor,
                UIColor.black.cgColor,
                UIColor.black.cgColor,
                UIColor.clear.cgColor]
            maskLayer.locations = [0.0, 0.33, 0.66, 1.0]
            maskLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
            maskLayer.endPoint = CGPoint(x: 0.0, y: 1.0)
            return maskLayer
        }()
        self.sizeCache.removeAll()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        self.sizeCache.removeAll()
        var snapshot = NSDiffableDataSourceSnapshot<Int, Value>()
        snapshot.appendSections([0])
        snapshot.appendItems(values, toSection: 0)

        diffDataSource.apply(snapshot, animatingDifferences: false, completion: nil)
        self.updateAccessibility()
    }


    private var layout: Layout<Center, Value>? {
        return self.collectionView.collectionViewLayout as? Layout<Center, Value>
    }

    private weak var collectionView: UICollectionView!

    func offsetForItem(at index: Int) -> CGFloat {
        var offset = self.layout?.originalAttributesForItem(at: IndexPath(item: index, section: 0))?.frame.midY ?? 0
        offset -= self.bounds.height / 2
        return offset
    }

    func select(value: Value) {
        if !self.collectionView.isDragging, !self.collectionView.isDecelerating,
           let index = self.values.firstIndex(of: value),
           index != selectedIndex {
            DispatchQueue.main.async {
                self.scrollToItem(at: index)
            }
        }
    }

    func scrollToItem(at index: Int, animated: Bool = true) {
        guard values.indices.contains(index) else {
            return
        }

        self.collectionView.setContentOffset(
            CGPoint(
                x: self.collectionView.contentOffset.x,
                y: offsetForItem(at: index)),
            animated: animated)
        self.selectedIndex = index
    }

    func didScroll(end: Bool) {
        let mid = CGRect(x: self.collectionView.contentOffset.x + self.bounds.width / 2,
                         y: self.collectionView.contentOffset.y + self.bounds.height / 2,
                        width: 1,
                        height: 1)
        let cells = collectionView.visibleCells.filter({ cell in
            cell.frame.intersects(mid)
         })
        .compactMap(self.collectionView.indexPath(for:))
         .sorted()

        if let index = cells.first?.item {
            if index != self.selectedIndex {
                self.selectionFeedback.selectionChanged()
            }
            self.selectedIndex = index
            if end {
                self.scrollToItem(at: index, animated: true)
            }
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        didScroll(end: true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        didScroll(end: !decelerate)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if self.collectionView.isDragging {
            self.didScroll(end: false)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.selectionFeedback.prepare()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard self.selectedIndex != indexPath.item else {
            return
        }

        self.selectionFeedback.selectionChanged()

        if indexPath.item > selectedIndex {
            self.scrollToItem(at: indexPath.item - centerSize + 1)
        } else {
            self.scrollToItem(at: indexPath.item)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let number = collectionView.numberOfItems(inSection: section)
        let firstIndexPath = IndexPath(item: 0, section: section)
        let firstSize = self.collectionView(collectionView, layout: collectionViewLayout, sizeForItemAt: firstIndexPath)
        let lastIndexPath = IndexPath(item: number - 1, section: section)
        let lastSize = self.collectionView(collectionView, layout: collectionViewLayout, sizeForItemAt: lastIndexPath)
        return UIEdgeInsets(
            top: (collectionView.bounds.size.height - firstSize.height/2) / 2, left: 0,
            bottom: (collectionView.bounds.size.height - lastSize.height/2) / 2, right: 0
        )
    }

    private var sizeCache: [AnyHashable: CGSize] = [:]

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let value = self.diffDataSource.itemIdentifier(for: indexPath) else {
            return .zero
        }
        if let cached = sizeCache[value] {
            return cached
        } else {
            self.configureCell(sizingCell, value)
            let size = self.sizingCell.systemLayoutSizeFitting(CGSize(width: collectionView.bounds.width, height: 0))

            let new = CGSize(width: collectionView.bounds.width, height: size.height)
            sizeCache[value] = new
            return new
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }

}


