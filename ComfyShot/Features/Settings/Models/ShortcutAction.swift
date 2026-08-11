//
//  ShortcutAction.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/10/26.
//

import KeyboardShortcuts

enum ShortcutAction: String, CaseIterable, Identifiable {
    case captureScreen
    case captureArea
    case scrollingCapture

    var id: Self { self }

    var label: String {
        switch self {
        case .captureScreen: "Capture Screen"
        case .captureArea: "Capture Area"
        case .scrollingCapture: "Scrolling Capture"
        }
    }

    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .captureScreen: .captureScreen
        case .captureArea: .captureArea
        case .scrollingCapture: .scrollingCapture
        }
    }
}
