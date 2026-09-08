//
//  UserImage.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import AppKit
import UniformTypeIdentifiers

struct UserImage: Identifiable {
    let id = UUID()
    let image: CGImage
    let size: NSSize
    var dragURL: URL?

    init(image: CGImage, size: NSSize) async {
        self.image = image
        self.size = size
        await generateDragURL()
    }

    mutating func generateDragURL() async {
        self.dragURL = await UserImageExportStore.shared.dragURL(
            for: id,
            image: image
        )
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
