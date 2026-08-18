//
//  ImageContainer.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/10/26.
//

import SwiftUI

struct ImageContainer: View {
    
    @Bindable var model: DisplayImageStackModel
    let placement: ImageStackPlacement
    let spacing: CGFloat
    let layout: ImageStackOverflowLayout
    let onClose: (UserImage) -> Void
    let onEditImage: (UserImage) -> Void
    @State private var pendingGalleryCollapse: Task<Void, Never>?
    
    private var galleryAnimation: Animation {
        .easeOut(duration: 0.15)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            
            // when the images overflow, this will never be empty
            // this is where all the old images will flow into
            // as new images render in the `UserImageView`
            if !layout.overflowImages.isEmpty {
                OverflowSection(
                    model: model,
                    placement: placement,
                    layout: layout,
                    pendingGalleryCollapse: $pendingGalleryCollapse,
                    onClose: onClose,
                    onEditImage: onEditImage
                )
            }
            
            ForEach(layout.visibleImages) { userImage in
                UserImageView(
                    id: userImage.id,
                    image: userImage.image,
                    size: userImage.size,
                    onClose: { onClose(userImage) },
                    onEditImage: { onEditImage(userImage) }
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
        .onDisappear {
            pendingGalleryCollapse?.cancel()
        }
    }
}
