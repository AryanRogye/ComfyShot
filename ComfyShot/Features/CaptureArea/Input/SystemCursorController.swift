//
//  SystemCursorController.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/9/26.
//

import AppKit

/// Sets the native cursor while capture panels remain non-key.
final class SystemCursorController {
    enum Shape: Equatable {
        case crosshair
        case openHand
        case closedHand
        case resize(CaptureResizeEdge)

        var cursor: NSCursor {
            switch self {
            case .crosshair: .crosshair
            case .openHand: .openHand
            case .closedHand: .closedHand
            case .resize(let edge): CaptureCursorOverride.resizeCursor(for: edge)
            }
        }
    }

    private var hasEnabledBackgroundCursorControl = false
    private var currentShape: Shape?

    func setCursor(_ shape: Shape, force: Bool = false) {
        guard force || shape != currentShape else { return }
        enableBackgroundCursorControlIfNeeded()
        CaptureCursorOverride.setInterceptedCursor(shape.cursor)
        currentShape = shape
    }

    func stop() {
        CaptureCursorOverride.clearInterceptedCursor()
        currentShape = nil
    }

    private func enableBackgroundCursorControlIfNeeded() {
        guard !hasEnabledBackgroundCursorControl else { return }

        let connection = CGSDefaultConnection()
        let result = CGSSetConnectionProperty(
            connection,
            connection,
            "SetsCursorInBackground" as CFString,
            kCFBooleanTrue
        )

        if result == .success {
            hasEnabledBackgroundCursorControl = true
        } else {
            print("Could not enable background cursor control: \(result.rawValue)")
        }
    }
}
