//
//  UserImageListView.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import SwiftUI

struct UserImageListView: View {
    
    @Bindable var model: DisplayImageStackModel
    let spacing: CGFloat
    let placement: ImageStackPlacement
    let onClose: (UserImage) -> Void
    
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
    }
    
    private var imageScrollView: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(images) { userImage in
                UserImageView(image: userImage.image, size: userImage.size, onClose: {
                    onClose(userImage)
                })
                .id(userImage.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
    }
    
    private var contentWidth: CGFloat {
        images.map(\.size.width).max() ?? 1
    }
    
    private var contentHeight: CGFloat {
        images.reduce(CGFloat.zero) { height, image in
            height + image.size.height
        } + spacing * CGFloat(max(images.count - 1, 0))
    }
    
    private func scrollToLatestImage(with proxy: ScrollViewProxy) {
        guard let latestImage = images.last else { return }
        
        DispatchQueue.main.async {
            proxy.scrollTo(latestImage.id, anchor: .bottom)
        }
    }
}
