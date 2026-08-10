//
//  UserImageListView.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import SwiftUI

struct UserImageListView: View {

    private enum Metrics {
        static let trayHeight: CGFloat = 52
        static let trayWidth: CGFloat = 132
        static let galleryHeight: CGFloat = 118
        static let gallerySpacing: CGFloat = 10
        static let thumbnailMaxWidth: CGFloat = 168
        static let thumbnailMaxHeight: CGFloat = 104
        static let galleryCollapseDelay = Duration.milliseconds(150)
    }
    
    @Bindable var model: DisplayImageStackModel
    let spacing: CGFloat
    let placement: ImageStackPlacement
    let onClose: (UserImage) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingGalleryCollapse: Task<Void, Never>?
    
    var images: [UserImage] {
        model.images
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            
            imageScrollView
                .frame(
                    width: contentWidth,
                    alignment: .bottomLeading
                )
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, placement.leadingInset)
                .padding(.bottom, placement.bottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            pendingGalleryCollapse?.cancel()
        }
    }
    
    private var imageScrollView: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if !layout.overflowImages.isEmpty {
                overflowSection
            }

            ForEach(layout.visibleImages) { userImage in
                UserImageView(
                    id: userImage.id,
                    image: userImage.image,
                    size: userImage.size,
                    onClose: { onClose(userImage) }
                )
                .id(userImage.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .animation(galleryAnimation, value: model.isOverflowGalleryPresented)
        .onChange(of: layout.overflowImages.isEmpty) { _, overflowIsEmpty in
            if overflowIsEmpty {
                model.setOverflowGalleryPresented(false)
            }
        }
    }

    private var overflowSection: some View {
        ZStack(alignment: .bottomLeading) {
            overflowTray

            if model.isOverflowGalleryPresented {
                overflowGallery
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.82, anchor: .leading)),
                                removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading))
                            )
                    )
            }
        }
        .frame(
            width: model.isOverflowGalleryPresented ? galleryWidth : Metrics.trayWidth,
            height: model.isOverflowGalleryPresented ? Metrics.galleryHeight : Metrics.trayHeight,
            alignment: .bottomLeading
        )
        .contentShape(Rectangle())
        .onHover(perform: handleGalleryHover)
        .accessibilityElement(children: .contain)
    }

    private var overflowTray: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.secondary.opacity(0.22))
                    .frame(width: 36, height: 27)
                    .rotationEffect(.degrees(-5))
                    .offset(x: -3, y: -2)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.secondary.opacity(0.34))
                    .frame(width: 36, height: 27)
                    .rotationEffect(.degrees(4))
                    .offset(x: 3, y: 1)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 42, height: 32)

            Text("\(layout.overflowImages.count) more")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(width: Metrics.trayWidth, height: Metrics.trayHeight, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        .opacity(model.isOverflowGalleryPresented ? 0 : 1)
        .allowsHitTesting(!model.isOverflowGalleryPresented)
        .onTapGesture {
            withAnimation(galleryAnimation) {
                model.setOverflowGalleryPresented(true)
            }
        }
        .accessibilityLabel("\(layout.overflowImages.count) older screenshots")
        .accessibilityHint("Hover or press to reveal")
        .accessibilityHidden(model.isOverflowGalleryPresented)
        .accessibilityAction(named: "Show older screenshots") {
            withAnimation(galleryAnimation) {
                model.setOverflowGalleryPresented(true)
            }
        }
    }

    private var overflowGallery: some View {
        AppKitOverflowGallery(
            images: layout.overflowImages,
            viewportSize: NSSize(width: galleryWidth, height: Metrics.galleryHeight),
            spacing: Metrics.gallerySpacing,
            thumbnailSize: thumbnailSize,
            rotation: fanRotation,
            verticalOffset: fanVerticalOffset,
            onClose: onClose
        )
        .frame(width: galleryWidth, height: Metrics.galleryHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 14, y: 7)
    }
    
    private var contentWidth: CGFloat {
        let recentWidth = layout.visibleImages.map(\.size.width).max() ?? 1
        if layout.overflowImages.isEmpty {
            return recentWidth
        }

        return max(
            recentWidth,
            model.isOverflowGalleryPresented ? galleryWidth : Metrics.trayWidth
        )
    }
    
    private var layout: ImageStackOverflowLayout {
        ImageStackOverflowLayout(
            images: images,
            maxHeight: placement.maxHeight,
            spacing: spacing,
            trayHeight: Metrics.trayHeight
        )
    }

    private var galleryWidth: CGFloat {
        let thumbnailWidths = layout.overflowImages.map { thumbnailSize(for: $0).width }
        let contentWidth = thumbnailWidths.reduce(0, +)
            + Metrics.gallerySpacing * CGFloat(max(thumbnailWidths.count - 1, 0))
            + 14
        return min(placement.maxWidth, max(Metrics.trayWidth, contentWidth))
    }

    private var galleryAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28)
    }

    private func handleGalleryHover(_ isHovering: Bool) {
        pendingGalleryCollapse?.cancel()

        if isHovering {
            withAnimation(galleryAnimation) {
                model.setOverflowGalleryPresented(true)
            }
            return
        }

        pendingGalleryCollapse = Task { @MainActor in
            try? await Task.sleep(for: Metrics.galleryCollapseDelay)
            guard !Task.isCancelled else { return }
            withAnimation(galleryAnimation) {
                model.setOverflowGalleryPresented(false)
            }
        }
    }

    private func thumbnailSize(for userImage: UserImage) -> NSSize {
        let scale = min(
            1,
            Metrics.thumbnailMaxWidth / userImage.size.width,
            Metrics.thumbnailMaxHeight / userImage.size.height
        )
        return NSSize(
            width: max(1, userImage.size.width * scale),
            height: max(1, userImage.size.height * scale)
        )
    }

    private func fanRotation(for index: Int) -> Double {
        guard !reduceMotion else { return 0 }
        return index.isMultiple(of: 2) ? -1.2 : 1.2
    }

    private func fanVerticalOffset(for index: Int) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return index.isMultiple(of: 2) ? -1 : 1
    }

}

struct ImageStackOverflowLayout {
    let visibleImages: [UserImage]
    let overflowImages: [UserImage]

    init(images: [UserImage], maxHeight: CGFloat, spacing: CGFloat, trayHeight: CGFloat) {
        let fullHeight = images.reduce(CGFloat.zero) { $0 + $1.size.height }
            + spacing * CGFloat(max(images.count - 1, 0))

        guard fullHeight > maxHeight else {
            visibleImages = images
            overflowImages = []
            return
        }

        let availableImageHeight = max(0, maxHeight - trayHeight - spacing)
        var usedHeight: CGFloat = 0
        var visibleStartIndex = images.count

        for index in images.indices.reversed() {
            let imageHeight = images[index].size.height
            let proposedHeight = usedHeight + (visibleStartIndex == images.count ? 0 : spacing) + imageHeight

            if proposedHeight > availableImageHeight, visibleStartIndex < images.count {
                break
            }

            visibleStartIndex = index
            usedHeight = proposedHeight
        }

        visibleImages = Array(images[visibleStartIndex...])
        overflowImages = Array(images[..<visibleStartIndex])
    }
}
