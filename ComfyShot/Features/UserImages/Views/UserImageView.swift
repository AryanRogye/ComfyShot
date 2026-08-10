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
    var shadowStyle: ShadowStyle = .regular
    let onClose: () -> Void

    @State private var hovering: Bool = false
    @State private var dragURL: URL?

    var body: some View {
        ZStack {
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
                onClose: onClose
            )
        )
        .onHover { hovering in
            withAnimation(.smooth) {
                self.hovering = hovering
            }
        }
        .task(id: id) {
            dragURL = await UserImageExportStore.shared.dragURL(for: id, image: image)
        }
        .draggable(dragURL ?? URL(fileURLWithPath: "/dev/null"))
    }
}

// MARK: - Controls Modifier
private struct UserImageControlsModifier: ViewModifier {
    
    let hovering: Bool
    let dragURL: URL?
    let onClose: () -> Void
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if hovering, let dragURL {
                    Button {
                        NSWorkspace.shared.open(dragURL)
                    } label: {
                        Text("Open")
                            .fontWeight(.bold)
                            .foregroundStyle(.black)
                            .padding(4)
                            .glassEffect(.regular, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .fontWeight(.black)
                            .foregroundStyle(.black)
                            .padding(4)
                            .glassEffect(.regular, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
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

private actor UserImageExportStore {
    static let shared = UserImageExportStore()

    private var urlsByImageID: [UUID: URL] = [:]

    func dragURL(for id: UUID, image: CGImage) -> URL? {
        if let URL = urlsByImageID[id] {
            return URL
        }

        let URL = try? writePNGTempFile(from: image)
        urlsByImageID[id] = URL
        return URL
    }

    private func writePNGTempFile(from cgImage: CGImage) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "ImageExport", code: 1)
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ImageExport", code: 2)
        }

        return url
    }
}
