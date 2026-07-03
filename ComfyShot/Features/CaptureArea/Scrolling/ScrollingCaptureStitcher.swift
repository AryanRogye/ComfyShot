//
//  ScrollingCaptureStitcher.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import CoreGraphics

struct ScrollingCaptureFrame {
    let image: CGImage
    let y: Int

    var width: Int {
        image.width
    }

    var height: Int {
        image.height
    }
}

struct ScrollingCaptureStitcher {
    static func compose(frames: [ScrollingCaptureFrame], gapTolerance: Int) -> CGImage? {
        guard let firstFrame = frames.first else { return nil }
        guard frames.allSatisfy({ $0.width == firstFrame.width }) else { return nil }

        var pieces: [StitchPiece] = []
        var filledBottom = 0

        for frame in frames.sorted(by: { $0.y < $1.y }) {
            let frameTop = max(0, frame.y)
            let frameBottom = frame.y + frame.height
            guard frameBottom > filledBottom else {
                continue
            }

            if frameTop > filledBottom + gapTolerance {
                return nil
            }

            let pieceTop = max(filledBottom, frameTop)
            let cropY = max(0, pieceTop - frame.y)
            let cropHeight = frameBottom - pieceTop

            guard cropHeight > 0,
                  let croppedImage = frame.image.cropping(to: CGRect(
                    x: 0,
                    y: cropY,
                    width: frame.width,
                    height: cropHeight
                  ))
            else {
                continue
            }

            pieces.append(StitchPiece(
                image: croppedImage,
                visualY: pieceTop,
                height: cropHeight
            ))
            filledBottom = frameBottom
        }

        guard filledBottom > 0,
              let context = CGContext(
                data: nil,
                width: firstFrame.width,
                height: filledBottom,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: rgbaBitmapInfo
              )
        else {
            return nil
        }

        context.interpolationQuality = .none

        for piece in pieces {
            let drawY = filledBottom - piece.visualY - piece.height
            context.draw(piece.image, in: CGRect(
                x: 0,
                y: drawY,
                width: piece.image.width,
                height: piece.height
            ))
        }

        return context.makeImage()
    }

    static func imageDifferenceScore(_ firstImage: CGImage, _ secondImage: CGImage) -> Double {
        guard let firstFingerprint = imageFingerprint(firstImage),
              let secondFingerprint = imageFingerprint(secondImage),
              firstFingerprint.count == secondFingerprint.count,
              !firstFingerprint.isEmpty
        else {
            return 0
        }

        var totalDifference = 0
        for index in firstFingerprint.indices {
            totalDifference += abs(Int(firstFingerprint[index]) - Int(secondFingerprint[index]))
        }

        return Double(totalDifference) / Double(firstFingerprint.count)
    }
}

private extension ScrollingCaptureStitcher {
    struct StitchPiece {
        let image: CGImage
        let visualY: Int
        let height: Int
    }

    static func imageFingerprint(_ image: CGImage) -> [UInt8]? {
        let width = 64
        let height = 64
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: rgbaBitmapInfo
                  )
            else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return rendered ? pixels : nil
    }

    static var rgbaBitmapInfo: UInt32 {
        CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    }
}
