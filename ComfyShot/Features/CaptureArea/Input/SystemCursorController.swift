//
//  SystemCursorController.swift
//  ComfyShot
//

import AppKit
import Darwin

/// Hides the hardware cursor while the capture overlay draws its replacement.
final class SystemCursorController {
    private typealias CursorVisibilityFunction = @convention(c) () -> Int32
    private static let cursorIsVisible: CursorVisibilityFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGCursorIsVisible") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CursorVisibilityFunction.self)
    }()
    private var hasEnabledBackgroundCursorControl = false
    private var hasParkedHardwareCursor = false
    private var cursorEnforcementTimer: Timer?
    private var systemCursorHideCount = 0
    private let virtualMouseLocation: () -> CGPoint
    private let isRunning: () -> Bool

    init(virtualMouseLocation: @escaping () -> CGPoint, isRunning: @escaping () -> Bool) {
        self.virtualMouseLocation = virtualMouseLocation
        self.isRunning = isRunning
    }

    /// Returns whether parking may produce a synthetic movement delta.
    @discardableResult
    func hideSystemCursor() -> Bool {
        guard isRunning(), systemCursorHideCount == 0 else { return false }

        enableBackgroundCursorControlIfNeeded()
        let screen = NSScreen.screens.first { $0.frame.contains(virtualMouseLocation()) } ?? NSScreen.main
        guard let screen else { return false }
        let parkingPoint = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        hasParkedHardwareCursor = CGWarpMouseCursorPosition(parkingPoint.quartzPoint) == .success
        hideVisibleSystemCursor()

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.isRunning() else { return }
            self.hideVisibleSystemCursor()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        cursorEnforcementTimer = timer
        return hasParkedHardwareCursor
    }

    func showSystemCursor() {
        guard hasParkedHardwareCursor || systemCursorHideCount > 0 || cursorEnforcementTimer != nil else {
            return
        }
        cursorEnforcementTimer?.invalidate()
        cursorEnforcementTimer = nil

        if hasParkedHardwareCursor {
            _ = CGWarpMouseCursorPosition(virtualMouseLocation().quartzPoint)
            hasParkedHardwareCursor = false
        }
        for _ in 0..<systemCursorHideCount {
            _ = CGDisplayShowCursor(CGMainDisplayID())
        }
        systemCursorHideCount = 0
        _ = CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func hideVisibleSystemCursor() {
        if let cursorIsVisible = Self.cursorIsVisible {
            guard cursorIsVisible() != 0 else { return }
        } else {
            guard systemCursorHideCount == 0 else { return }
        }
        _ = CGDisplayHideCursor(CGMainDisplayID())
        systemCursorHideCount += 1
        _ = CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Non-key overlays need cursor control even while another app is active.
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
