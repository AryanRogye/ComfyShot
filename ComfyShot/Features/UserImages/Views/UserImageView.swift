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
    @State private var shadowImage: CGImage?

    var body: some View {
        ZStack {
            if let shadowImage {
                Image(decorative: shadowImage, scale: 1)
                    .resizable()
                    .frame(
                        width: size.width + Self.shadowOutset * 2,
                        height: size.height + Self.shadowOutset * 2
                    )
                    .allowsHitTesting(false)
            }
            
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
                .clipShape(imageShape)
                .overlay {
                    imageShape
                        .stroke(.black.opacity(0.46), lineWidth: 2)
                }
                .overlay {
                    if hovering {
                        imageShape
                            .fill(Color.black.opacity(0.5))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if hovering, let dragURL {
                        Button {
                            NSWorkspace.shared.open(dragURL)
                        } label: {
                            Text("Open")
                                .fontWeight(.bold)
                                .foregroundStyle(.black)
                                .padding(4)
                                .background(.white.opacity(0.6), in: .rect(cornerRadius: 8))
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
                                .background(.white.opacity(0.6), in: .rect(cornerRadius: 8))
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
            shadowImage = makeShadowImage(color: .black, blur: 18, y: -4)
        }
        .onChange(of: size) {
            shadowImage = makeShadowImage(color: .black, blur: 18, y: -4)
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
    
    private func makeShadowImage(
        color: Color,
        blur: CGFloat,
        x: CGFloat = 0,
        y: CGFloat = 0,
    ) -> CGImage? {
        let canvasSize = CGSize(
            width: size.width + Self.shadowOutset * 2,
            height: size.height + Self.shadowOutset * 2
        )
        let width = max(1, Int(canvasSize.width.rounded(.up)))
        let height = max(1, Int(canvasSize.height.rounded(.up)))
        
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        context.setFillColor(NSColor.black.cgColor)
        context.setShadow(
            offset: CGSize(width: x, height: y),
            blur: blur,
            color: color.resolve(in: environment).cgColor
        )

        let imageRect = CGRect(
            x: Self.shadowOutset,
            y: Self.shadowOutset,
            width: size.width,
            height: size.height
        )
        context.addPath(
            CGPath(
                roundedRect: imageRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
        )
        context.fillPath()
        
        return context.makeImage()
    }
}
