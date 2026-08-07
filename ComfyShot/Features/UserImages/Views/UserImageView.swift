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

    @Environment(\.self) var environment
    
    static let shadowOutset: CGFloat = 32
    private let cornerRadius: CGFloat = 16

    let image: CGImage
    let size: NSSize
    let onClose: () -> Void

    @State private var hovering: Bool = false
    @State private var dragURL: URL?

    var body: some View {
        ZStack {
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
                .clipShape(imageShape)
                .shadow(
                    color: .black.opacity(0.25),
                    radius: 3,
                    x: 0,
                    y: 2
                )
                .shadow(
                    color: .black.opacity(0.48),
                    radius: 12.5,
                    x: 0,
                    y: 5
                )
                .shadow(
                    color: .black.opacity(0.28),
                    radius: 22,
                    x: 0,
                    y: 10
                )
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
        .frame(
            width: size.width,
            height: size.height
        )
        .onHover { hovering in
            withAnimation(.smooth) {
                self.hovering = hovering
            }
        }
        .onAppear {
            dragURL = try? writePNGTempFile(from: image)
        }
        .draggable(dragURL ?? URL(fileURLWithPath: "/dev/null"))
    }
    
    private var imageShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
