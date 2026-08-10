//
//  UserImageListView.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import SwiftUI

enum Metrics {
    static let trayHeight: CGFloat = 52
    static let trayWidth: CGFloat = 132
    static let galleryHeight: CGFloat = 118
    static let gallerySpacing: CGFloat = 10
    static let thumbnailMaxWidth: CGFloat = 168
    static let thumbnailMaxHeight: CGFloat = 104
    static let galleryCollapseDelay = Duration.milliseconds(150)
}

struct UserImageListView: View {
    
    @Bindable var model: DisplayImageStackModel
    let spacing: CGFloat
    let placement: ImageStackPlacement
    let onClose: (UserImage) -> Void

    var images: [UserImage] {
        model.images
    }
    
    private var layout: ImageStackOverflowLayout {
        ImageStackOverflowLayout(
            images: images,
            maxHeight: placement.maxHeight,
            spacing: spacing,
            trayHeight: Metrics.trayHeight
        )
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            
            ImageContainer(
                model: model,
                placement: placement,
                spacing: spacing,
                layout: layout,
                onClose: onClose
            )
            .frame(
                width: contentWidth,
                alignment: .bottomLeading
            )
            .frame(maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, placement.leadingInset)
            .padding(.bottom, placement.bottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    
    private var galleryWidth: CGFloat {
        let thumbnailWidths = layout.overflowImages.map { thumbnailSize(for: $0).width }
        let contentWidth = thumbnailWidths.reduce(0, +)
            + Metrics.gallerySpacing * CGFloat(max(thumbnailWidths.count - 1, 0))
            + 14
        return min(placement.maxWidth, max(Metrics.trayWidth, contentWidth))
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
}

/// Splits a display's screenshots into two ordered groups:
///
/// - `visibleImages`: The newest screenshots that fit in the vertical stack.
/// - `overflowImages`: Older screenshots represented by the "N more" tray.
///
/// Both arrays preserve the original oldest-to-newest ordering from `images`.
/// This type only calculates the partition; it does not modify or remove images.
struct ImageStackOverflowLayout {
    let visibleImages: [UserImage]
    let overflowImages: [UserImage]

    init(images: [UserImage], maxHeight: CGFloat, spacing: CGFloat, trayHeight: CGFloat) {
        // First check whether the complete stack fits without an overflow tray.
        // There is one spacing gap between each neighboring pair of images.
        let fullHeight = images.reduce(CGFloat.zero) { $0 + $1.size.height }
            + spacing * CGFloat(max(images.count - 1, 0))

        guard fullHeight > maxHeight else {
            visibleImages = images
            overflowImages = []
            return
        }

        // Overflow exists, so reserve enough vertical room for the tray and
        // the gap between the tray and the first visible screenshot.
        let availableImageHeight = max(0, maxHeight - trayHeight - spacing)
        var usedHeight: CGFloat = 0
        var visibleStartIndex = images.count

        // Walk backward because the newest screenshots have priority. Each
        // accepted image moves the beginning of the visible slice leftward.
        for index in images.indices.reversed() {
            let imageHeight = images[index].size.height
            let proposedHeight = usedHeight + (visibleStartIndex == images.count ? 0 : spacing) + imageHeight

            // Stop before adding an image that would exceed the available
            // height. The second condition deliberately lets the newest image
            // through even when it is taller than the available space, so the
            // user never ends up with a tray and no directly visible capture.
            if proposedHeight > availableImageHeight, visibleStartIndex < images.count {
                break
            }

            visibleStartIndex = index
            usedHeight = proposedHeight
        }

        // Everything before the split is older overflow content; everything
        // from the split onward is the newest content displayed in the stack.
        visibleImages = Array(images[visibleStartIndex...])
        overflowImages = Array(images[..<visibleStartIndex])
    }
}
