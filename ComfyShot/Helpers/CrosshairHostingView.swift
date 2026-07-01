//
//  CrosshairHostingView.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//  Ensures a crosshair cursor over the entire hosting view.
//

import AppKit
import SwiftUI

@MainActor
enum CaptureCursorOverride {
    private static var cursor: NSCursor?
    
    static func setResizeUpDown() {
        set(.resizeUpDown)
    }
    
    static func setResizeLeftRight() {
        set(.resizeLeftRight)
    }
    
    static func setOpenHand() {
        set(.openHand)
    }
    
    static func setClosedHand() {
        set(.closedHand)
    }
    
    static func clear() {
        set(nil)
    }
    
    static func current(default defaultCursor: NSCursor) -> NSCursor {
        cursor ?? defaultCursor
    }
    
    private static func set(_ newCursor: NSCursor?) {
        cursor = newCursor
        current(default: .crosshair).set()
    }
}

final class CrosshairHostingView<Content: View>: NSHostingView<Content> {
    private var trackingArea: NSTrackingArea?
    
    private var currentCursor: NSCursor {
        CaptureCursorOverride.current(default: .crosshair)
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: currentCursor)
    }
    
    override func cursorUpdate(with event: NSEvent) {
        currentCursor.set()
    }
    
    override func mouseMoved(with event: NSEvent) {
        currentCursor.set()
        super.mouseMoved(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        currentCursor.set()
        super.mouseDragged(with: event)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)
        currentCursor.set()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .cursorUpdate,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }
}
