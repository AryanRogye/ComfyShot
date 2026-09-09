//
//  SystemCursorController.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/9/26.
//

import AppKit

final class SystemCursorController {

    private var hasEnabledBackgroundCursorControl = false
    private var hasParkedHardwareCursor = false
    private var cursorEnforcementTimer: Timer?
    private var systemCursorHideCount = 0

    private let onGetIsRunning: () -> Bool
    private let onGetVirtualMouseLocation: () -> CGPoint

    init(
        onGetVirtualMouseLocation: @escaping () -> CGPoint,
        onGetIsRunning: @escaping () -> Bool
    ) {
        self.onGetVirtualMouseLocation = onGetVirtualMouseLocation
        self.onGetIsRunning = onGetIsRunning
    }
}

// MARK: - Cursor Visibility

extension SystemCursorController {

    func hideSystemCursor() {
        guard onGetIsRunning(), systemCursorHideCount == 0 else { return }

        enableBackgroundCursorControlIfNeeded()
        parkHardwareCursorOutsideDock()
        hideVisibleSystemCursor()
        beginCursorVisibilityEnforcement()
    }

    /// Restores the pointer at the final virtual position, then balances every
    /// Quartz hide owned by this capture session.
    func showSystemCursor() {
        cursorEnforcementTimer?.invalidate()
        cursorEnforcementTimer = nil

        if hasParkedHardwareCursor {
            _ = CGWarpMouseCursorPosition(
                onGetVirtualMouseLocation().quartzPoint
            )

            hasParkedHardwareCursor = false
        }

        for _ in 0..<systemCursorHideCount {
            _ = CGDisplayShowCursor(CGMainDisplayID())
        }

        systemCursorHideCount = 0
        _ = CGAssociateMouseAndMouseCursorPosition(1)
    }
}

// MARK: - Background Cursor Control

extension SystemCursorController {

    /// Allows ComfyShot to change cursor state without activating its panels.
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

// MARK: - Hardware Cursor Parking

extension SystemCursorController {

    /// Moves the hardware pointer away from the Dock without sending a movement
    /// event. The Dock keeps its last hover state, but no longer owns the cursor
    /// sprite that it otherwise draws over a successful global hide.
    private func parkHardwareCursorOutsideDock() {
        guard !hasParkedHardwareCursor else { return }

        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(onGetVirtualMouseLocation())
        }) ?? NSScreen.main else {
            return
        }

        let parkingPoint = CGPoint(
            x: screen.frame.midX,
            y: screen.frame.midY
        )

        let result = CGWarpMouseCursorPosition(
            parkingPoint.quartzPoint
        )

        hasParkedHardwareCursor = result == .success
    }
}

// MARK: - Cursor Visibility Enforcement

extension SystemCursorController {

    /// Starts a watchdog because applications and system UI may make the cursor
    /// visible later. Checking first prevents the hide counter growing each tick.
    private func beginCursorVisibilityEnforcement() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, onGetIsRunning() else { return }

            hideVisibleSystemCursor()
        }

        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)

        cursorEnforcementTimer = timer
    }

    /// Adds one owned Quartz hide only when WindowServer currently draws a cursor.
    private func hideVisibleSystemCursor() {
        guard CGCursorIsVisible() != 0 else { return }

        _ = CGDisplayHideCursor(CGMainDisplayID())
        systemCursorHideCount += 1

        /// Reassociation makes WindowServer refresh the cursor sprite immediately
        /// instead of leaving the last rendered image behind.
        _ = CGAssociateMouseAndMouseCursorPosition(1)
    }
}
