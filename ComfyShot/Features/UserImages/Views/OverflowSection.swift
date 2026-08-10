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
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            overflowTray
            
            if model.isOverflowGalleryPresented {
                overflowGallery
                    .transition(
                        .asymmetric(
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
    
    private func fanVerticalOffset(for index: Int) -> CGFloat {
        return index.isMultiple(of: 2) ? -1 : 1
    }
    
    private func fanRotation(for index: Int) -> Double {
        return index.isMultiple(of: 2) ? -1.2 : 1.2
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
}
