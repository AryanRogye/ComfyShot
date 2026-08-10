//
//  OverflowSection.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/10/26.
//

import SwiftUI

struct OverflowSection: View {
    
    @Bindable var model: DisplayImageStackModel
    let placement: ImageStackPlacement
    let layout: ImageStackOverflowLayout
    @Binding var pendingGalleryCollapse: Task<Void, Never>?
    let onClose: (UserImage) -> Void
    
    private var galleryAnimation: Animation {
        .easeOut(duration: 0.15)
    }
    
    private var galleryWidth: CGFloat {
        let thumbnailWidths = layout.overflowImages.map { thumbnailSize(for: $0).width }
        let contentWidth = thumbnailWidths.reduce(0, +)
        + Metrics.gallerySpacing * CGFloat(max(thumbnailWidths.count - 1, 0))
        + 14
        return min(placement.maxWidth, max(Metrics.trayWidth, contentWidth))
    }
    
    @Namespace var nm
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if !model.isOverflowGalleryPresented {
                overflowTray
                    .matchedGeometryEffect(id: "overflow-tray", in: nm)
            }
            
            if model.isOverflowGalleryPresented {
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
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.82, anchor: .leading)),
                        removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading))
                    )
                )
                .matchedGeometryEffect(id: "overflow-tray", in: nm)
            }
        }
        .frame(
            width: model.isOverflowGalleryPresented ? galleryWidth : Metrics.trayWidth,
            height: model.isOverflowGalleryPresented ? Metrics.galleryHeight : Metrics.trayHeight,
            alignment: .bottomLeading
        )
        .contentShape(Rectangle())
        .onHover { isHovering in
            // cancel any hovering transitions of collapsing
            pendingGalleryCollapse?.cancel()
            
            // if we're hovering show the full tray
            if isHovering {
                withAnimation(galleryAnimation) {
                    model.setOverflowGalleryPresented(true)
                }
                return
            }
            
            // collapse task with delay + animation
            pendingGalleryCollapse = Task { @MainActor in
                try? await Task.sleep(for: Metrics.galleryCollapseDelay)
                guard !Task.isCancelled else { return }
                withAnimation(galleryAnimation) {
                    model.setOverflowGalleryPresented(false)
                }
            }
        }
    }

    private var overflowTray: some View {
        HStack(spacing: 10) {
            ZStack {
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
        .frame(
            width: Metrics.trayWidth,
            height: Metrics.trayHeight,
            alignment: .leading
        )
        .background(
            .regularMaterial,
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .strokeBorder(.primary.opacity(0.36), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }
}

fileprivate func thumbnailSize(for userImage: UserImage) -> NSSize {
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

fileprivate func fanVerticalOffset(for index: Int) -> CGFloat {
    return index.isMultiple(of: 2) ? -1 : 1
}

fileprivate func fanRotation(for index: Int) -> Double {
    return index.isMultiple(of: 2) ? -1.2 : 1.2
}
