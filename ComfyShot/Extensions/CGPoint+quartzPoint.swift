//
//  CGPoint+quartzPoint.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/9/26.
//

import AppKit

extension CGPoint {
    public var quartzPoint: CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(self) }),
              let displayID = screen.displayID else { return self }

        let quartzFrame = CGDisplayBounds(displayID)
        return CGPoint(
            x: quartzFrame.minX + self.x - screen.frame.minX,
            y: quartzFrame.minY + screen.frame.maxY - self.y
        )
    }
}
