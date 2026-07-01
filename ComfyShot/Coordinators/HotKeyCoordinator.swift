//
//  HotKeyCoordinator.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import KeyboardShortcuts
import Cocoa

extension KeyboardShortcuts.Name {
    static let captureScreen = Self(
        "CaptureScreen",
        initial: .init(.one, modifiers: [.command, .shift])
    )
    static let captureArea = Self(
        "CaptureArea",
        initial: .init(.two, modifiers: [.command, .shift])
    )
    static let scrollingCapture = Self(
        "ScrollingCapture",
        initial: .init(.backtick, modifiers: [.command, .shift])
    )
}


@MainActor
final class HotKeyCoordinator {
    init() {}
    
    func start(
        onCaptureScreen: @escaping () -> Void,
        onCaptureArea: @escaping () -> Void,
        onScrollingCapture: @escaping () -> Void
    ) {
        KeyboardShortcuts.onKeyDown(for: .captureScreen) {
            onCaptureScreen()
        }
        KeyboardShortcuts.onKeyDown(for: .captureArea) {
            onCaptureArea()
        }
        KeyboardShortcuts.onKeyDown(for: .scrollingCapture) {
            onScrollingCapture()
        }
    }
}
