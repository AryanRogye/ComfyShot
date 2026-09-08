//
//  ImageContainer.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/10/26.
//

import SwiftUI
import Defaults

struct ImageContainer: View {
    
    @Bindable var model: DisplayImageStackModel
    let placement: ImageStackPlacement
    let spacing: CGFloat
    let layout: ImageStackOverflowLayout
    let onClose: (UserImage) -> Void
    let onEditImage: (UserImage) -> Void
    let onShiftClick: (UserImage) -> Void

    @Default(.dragPreviewFormation)
    var dragPreviewFormation: DragPreviewFormation

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
                    onEditImage: onEditImage,
                    onShiftClick: onShiftClick
                )
            }
            
            ForEach(layout.visibleImages) { userImage in
                UserImageView(
                    id: userImage.id,
                    image: userImage.image,
                    size: userImage.size,
                    isShiftClicked: model.shiftClickedImages.contains(where: { $0.id == userImage.id}),
                    dragURL: userImage.dragURL,
                    onClose: { onClose(userImage) },
                    onEditImage: { onEditImage(userImage) },
                    onShiftClick: { onShiftClick(userImage) }
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
        .dragContainer(for: DraggableImage.self) { draggedIDs in
            // The container can be dragging a selection that includes images in
            // the overflow gallery. Build the payload from the source-of-truth
            // collection instead of only the images currently visible in the
            // stack.
            let draggable: [DraggableImage] = model.images.compactMap { userImage in
                guard draggedIDs.contains(userImage.id) else {
                    return nil
                }

                let url = userImage.dragURL
                guard let url else {
                    return nil
                }

                return DraggableImage(
                    id: userImage.id,
                    url: url
                )
            }

            return draggable
        }
        .dragPreviewsFormation(dragPreviewFormation.formation)
        .dragContainerSelection(
            model.shiftClickedImages.map(\.id)
        )
        .onDragSessionUpdated { session in
            /// This checks to see if we did complete the drag, if we did
            /// we unshift click the items
            switch session.phase {
            case .ended(let operation):
                switch operation {
                case .copy:
                    model.unShiftClickedImages()
                default:
                    break
                }
            default:
                break
            }
        }
    }
}
