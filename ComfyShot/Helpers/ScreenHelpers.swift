//
//  ScreenHelpers.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import Cocoa

enum ScreenHelpers {
    /**
     * Grab the screen under the mouse
     */
    public static func screenUnderMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first {
            NSMouseInRect(loc, $0.frame, false)
        }
    }
    
    static func unionFrameOfAllScreens() -> CGRect? {
        let screens = NSScreen.screens
        guard let first = screens.first else { return nil }
        return screens.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }
    
    static func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
        ?? NSScreen.screens.first { $0.frame.intersects(rect) }
    }
}
