//
//  AppKitOverflowGallery.swift
//  ComfyShot
//

import AppKit
import SwiftUI

struct AppKitOverflowGallery: NSViewRepresentable {
    let images: [UserImage]
    let shiftClickedImages: [UserImage]
    let viewportSize: NSSize
    let spacing: CGFloat
    let thumbnailSize: (UserImage) -> NSSize
    let rotation: (Int) -> Double
    let verticalOffset: (Int) -> CGFloat
    let onClose: (UserImage) -> Void
    let onEditImage: (UserImage) -> Void
    let onShiftClick: (UserImage) -> Void
    let isShiftClicked: (UserImage) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NoScrollerScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = NSEdgeInsets(top: 7, left: 7, bottom: 7, right: 7)

        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(
            OverflowGalleryItem.self,
            forItemWithIdentifier: OverflowGalleryItem.reuseIdentifier
        )

        let scrollView = NoScrollerScrollView()
        scrollView.drawsBackground = false
        scrollView.documentView = collectionView
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScroller = nil
        scrollView.verticalScroller = nil
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()

        context.coordinator.collectionView = collectionView
        context.coordinator.scrollView = scrollView
        context.coordinator.reload(with: self, scrollToTrailingEdge: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NoScrollerScrollView, context: Context) {
        let previousIDs = context.coordinator.images.map(\.id)
        let currentIDs = images.map(\.id)

        let currentShiftClicked   = shiftClickedImages.map(\.id)
        let oldShiftClickedImages = context.coordinator.shiftClickedImages.map(\.id)

        let contentChanged = previousIDs != currentIDs
        let selectionChanged = currentShiftClicked != oldShiftClickedImages

        context.coordinator.reload(
            with: self,
            reloadData: contentChanged || selectionChanged,
            scrollToTrailingEdge: contentChanged
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        fileprivate var images: [UserImage]
        fileprivate var shiftClickedImages: [UserImage]
        fileprivate var thumbnailSize: (UserImage) -> NSSize
        fileprivate var rotation: (Int) -> Double
        fileprivate var verticalOffset: (Int) -> CGFloat
        fileprivate var onClose: (UserImage) -> Void
        fileprivate var onEditImage: (UserImage) -> Void
        fileprivate var onShiftClick: (UserImage) -> Void

        fileprivate weak var collectionView: NSCollectionView?
        fileprivate weak var scrollView: NSScrollView?

        init(parent: AppKitOverflowGallery) {
            images = parent.images
            thumbnailSize = parent.thumbnailSize
            rotation = parent.rotation
            verticalOffset = parent.verticalOffset
            onClose = parent.onClose
            onEditImage = parent.onEditImage
            onShiftClick = parent.onShiftClick
            shiftClickedImages = parent.shiftClickedImages
        }

        fileprivate func reload(
            with parent: AppKitOverflowGallery,
            reloadData: Bool = true,
            scrollToTrailingEdge: Bool
        ) {
            images = parent.images
            shiftClickedImages = parent.shiftClickedImages

            thumbnailSize = parent.thumbnailSize
            rotation = parent.rotation
            verticalOffset = parent.verticalOffset

            onClose = parent.onClose
            onEditImage = parent.onEditImage
            onShiftClick = parent.onShiftClick

            if reloadData {
                collectionView?.reloadData()
            }
            collectionView?.frame.size.height = parent.viewportSize.height

            guard scrollToTrailingEdge else { return }
            DispatchQueue.main.async { [weak self] in
                self?.scrollToTrailingEdge()
            }
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            images.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            guard let item = collectionView.makeItem(
                withIdentifier: OverflowGalleryItem.reuseIdentifier,
                for: indexPath
            ) as? OverflowGalleryItem else {
                return NSCollectionViewItem()
            }

            let image = images[indexPath.item]
            item.configure(
                with: image,
                size: thumbnailSize(image),
                rotation: rotation(indexPath.item),
                verticalOffset: verticalOffset(indexPath.item),
                position: indexPath.item,
                count: images.count,
                isShiftClicked: shiftClickedImages.contains(where: { $0.id == image.id }),
                onClose: { [weak self] image in
                    guard let self else { return }
                    self.onClose(image)
                },
                onEditImage: { [weak self] image in
                    guard let self else { return }
                    self.onEditImage(image)
                },
                onShiftClick: { [weak self] image in
                    guard let self else { return }
                    self.onShiftClick(image)
                }
            )
            return item
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> NSSize {
            thumbnailSize(images[indexPath.item])
        }

        private func scrollToTrailingEdge() {
            guard let scrollView, let collectionView else { return }
            collectionView.layoutSubtreeIfNeeded()

            let contentWidth = collectionView.collectionViewLayout?.collectionViewContentSize.width ?? 0
            let trailingX = max(0, contentWidth - scrollView.contentView.bounds.width)
            scrollView.contentView.scroll(to: NSPoint(x: trailingX, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

final class NoScrollerScrollView: NSScrollView {

    override var hasHorizontalScroller: Bool {
        get { false }
        set { super.hasHorizontalScroller = false }
    }

    override var hasVerticalScroller: Bool {
        get { false }
        set { super.hasVerticalScroller = false }
    }

    override var horizontalScroller: NSScroller? {
        get { nil }
        set { super.horizontalScroller = nil }
    }

    override var verticalScroller: NSScroller? {
        get { nil }
        set { super.verticalScroller = nil }
    }
}

@MainActor
private final class OverflowGalleryItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("OverflowGalleryItem")

    private var hostingView: NSHostingView<AnyView>?

    override func loadView() {
        let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = false
        view = hostingView
        self.hostingView = hostingView
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hostingView?.rootView = AnyView(EmptyView())
    }

    func configure(
        with userImage: UserImage,
        size: NSSize,
        rotation: Double,
        verticalOffset: CGFloat,
        position: Int,
        count: Int,
        isShiftClicked: Bool,
        onClose: @escaping (UserImage) -> Void,
        onEditImage: @escaping (UserImage) -> Void,
        onShiftClick: @escaping (UserImage) -> Void
    ) {
        hostingView?.rootView = AnyView(
            UserImageView(
                id: userImage.id,
                image: userImage.image,
                size: size,
                isShiftClicked: isShiftClicked,
                dragURL: userImage.dragURL,
                shadowStyle: .compact,
                onClose: { onClose(userImage) },
                onEditImage: { onEditImage(userImage) },
                onShiftClick: { onShiftClick(userImage) }
            )
            .rotationEffect(.degrees(rotation))
            .offset(y: verticalOffset)
        )
    }
}
