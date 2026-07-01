//
//  NSRect+axPosition.swift
//  ComfyTile
//
//  Created by Aryan Rogye on 1/9/26.
//

import Cocoa

extension NSRect {
    public func axPosition(
        on screen: NSScreen
    ) -> CGPoint {
        let rect = self
        let mainDisplayTopY = NSScreen.screens
            .first { $0.frame.origin == .zero }?
            .frame
            .maxY
            ?? NSScreen.main?.frame.maxY
            ?? screen.frame.maxY
        
        let appKitTop = rect.maxY
        
        let axY = mainDisplayTopY - appKitTop
        
        return CGPoint(x: rect.origin.x, y: axY)
    }
}
