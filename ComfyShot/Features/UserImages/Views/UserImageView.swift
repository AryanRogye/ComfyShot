//
//  UserImageView.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct UserImageView: View {

    enum ShadowStyle {
        case regular
        case compact
    }

    static let shadowOutset: CGFloat = 32
    private let cornerRadius: CGFloat = 16

    let id: UUID
    let image: CGImage
    let size: NSSize
    let isShiftClicked: Bool
    let dragURL: URL?
    var shadowStyle: ShadowStyle = .regular
    let onClose: () -> Void
    let onEditImage: () -> Void
    let onShiftClick: () -> Void

    @State private var hovering: Bool = false

    var body: some View {
        ZStack {
            ShiftClickCapturable(didShiftClick: onShiftClick)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(0.12))

            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: size.width,
                    height: size.height
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .draggable(containerItemID: id)

            if isShiftClicked {
                Color.black.opacity(0.5)
                    .allowsHitTesting(false)
                ZStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 22, weight: .black, design: .default))
                                .foregroundStyle(.white)
                        }
                }
                .allowsHitTesting(false)
            }
        }
        .frame(
            width: size.width,
            height: size.height
        )
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .modifier(
            UserImageShadowModifier(style: shadowStyle)
        )
        .modifier(
            UserImageControlsModifier(
                hovering: hovering,
                dragURL: dragURL,
                onClose: onClose,
                onEditImage: onEditImage
            )
        )
        .onHover { hovering in
            withAnimation(.smooth) {
                self.hovering = hovering
            }
        }
        .animation(.spring, value: isShiftClicked)
    }
}

struct DraggableImage: Identifiable, Transferable {
    let id: UUID
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        // Keep the URL representation used by URL-based drop targets (the old
        // single-image drag exported URL directly), while also keeping a file
        // representation for Finder and image-aware targets.
        ProxyRepresentation(exporting: \.url)
        FileRepresentation(exportedContentType: .png) { item in
            SentTransferredFile(
                item.url,
                allowAccessingOriginalFile: true
            )
        }
    }
}

// MARK: - Controls Modifier
private struct UserImageControlsModifier: ViewModifier {

    let hovering: Bool
    let dragURL: URL?
    let onClose: () -> Void
    let onEditImage: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if hovering {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            if let dragURL {
                                Button {
                                    NSWorkspace.shared.open(dragURL)
                                } label: {
                                    Text("Open")
                                        .modifier(UserImageControlLabelModifier())
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer(minLength: 8)

                            HStack(spacing: 8) {
                                Button(action: onEditImage) {
                                    Image(systemName: "pencil.tip")
                                        .modifier(UserImageControlLabelModifier())
                                }
                                .buttonStyle(.plain)

                                Button(action: onClose) {
                                    Image(systemName: "xmark")
                                        .modifier(UserImageControlLabelModifier())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(8)
                }
            }
    }
}

private struct UserImageControlLabelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(4)
            .glassEffect(
                .regular
                    .tint(.black.opacity(0.42))
                    .interactive(),
                in: .rect(cornerRadius: 8)
            )
    }
}

// MARK: - Shadow Modifier
private struct UserImageShadowModifier: ViewModifier {
    let style: UserImageView.ShadowStyle

    func body(content: Content) -> some View {
        switch style {
        case .regular:
            content
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
                .shadow(color: .black.opacity(0.48), radius: 12.5, x: 0, y: 5)
                .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 10)
        case .compact:
            content
                .shadow(color: .black.opacity(0.34), radius: 6, x: 0, y: 3)
        }
    }
}
