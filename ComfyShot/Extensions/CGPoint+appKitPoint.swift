//
//  CGPoint+appKitPoint.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/9/26.
//

import AppKit

extension CGPoint {
    public var appKitPoint: CGPoint {
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let displayID = screen.displayID else { return false }
            return CGDisplayBounds(displayID).contains(self)
        }), let displayID = screen.displayID else { return self }

        let quartzFrame = CGDisplayBounds(displayID)
        return CGPoint(
            x: screen.frame.minX + x - quartzFrame.minX,
            y: screen.frame.maxY - (y - quartzFrame.minY)
        )
    }
}
