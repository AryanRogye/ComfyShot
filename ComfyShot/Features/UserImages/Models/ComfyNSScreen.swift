//
//  ComfyNSScreen.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/8/26.
//

import Cocoa

struct ComfyNSScreen: Sendable {

    let frame: NSRect
    let visibleFrame: NSRect

    var rawValue: String?

    init(screen: NSScreen) {
        self.frame = screen.frame
        self.visibleFrame = screen.visibleFrame
        self.rawValue = screen.rawValue
    }
}
