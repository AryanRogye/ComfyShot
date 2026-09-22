//
//  SystemCursorController.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/9/26.
//

import AppKit

/// Sets the native cursor while capture panels remain non-key.
final class SystemCursorController {
    private var hasEnabledBackgroundCursorControl = false

    func setCursor(_ cursor: NSCursor) {
        enableBackgroundCursorControlIfNeeded()
        CaptureCursorOverride.setInterceptedCursor(cursor)
    }

    func stop() {
        CaptureCursorOverride.clearInterceptedCursor()
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
