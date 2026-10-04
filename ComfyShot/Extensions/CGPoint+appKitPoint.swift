//
//  CGPoint+appKitPoint.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/9/26.
//

import AppKit

extension CGPoint {
    /// Converts an AppKit global point to Quartz display coordinates.
    var quartzPoint: CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(self) }),
              let displayID = screen.displayID else { return self }
        let frame = CGDisplayBounds(displayID)
        return CGPoint(
            x: frame.minX + x - screen.frame.minX,
            y: frame.minY + screen.frame.maxY - y
        )
    }

    public var appKitPoint: CGPoint {
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let displayID = screen.displayID else { return false }
            let bounds = CGDisplayBounds(displayID)
            return self.x >= bounds.minX && self.x <= bounds.maxX
                && self.y >= bounds.minY && self.y <= bounds.maxY
        }) ?? NSScreen.main, let displayID = screen.displayID else { return self }

        let quartzFrame = CGDisplayBounds(displayID)
        return CGPoint(
            x: screen.frame.minX + x - quartzFrame.minX,
            y: screen.frame.maxY - (y - quartzFrame.minY)
        )
    }
}
