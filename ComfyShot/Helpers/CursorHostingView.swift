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
    private static var interceptedCursor: NSCursor?
    
    static func setResizeUpDown() {
        set(resizeCursor(for: .top))
    }
    
    static func setResizeLeftRight() {
        set(resizeCursor(for: .leading))
    }

    static func setResizeTopLeftBottomRight() {
        set(resizeCursor(for: .topLeading))
    }

    static func setResizeTopRightBottomLeft() {
        set(resizeCursor(for: .topTrailing))
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
        interceptedCursor ?? cursor ?? defaultCursor
    }

    /// Keep the cursor rect and the intercepted input path on the same shape.
    static func setInterceptedCursor(_ newCursor: NSCursor) {
        interceptedCursor = newCursor
        newCursor.set()
    }

    static func clearInterceptedCursor() {
        interceptedCursor = nil
        cursor = nil
    }

    /// Returns the resize cursor used by both AppKit input paths.
    static func resizeCursor(for edge: CaptureResizeEdge) -> NSCursor {
        switch edge {
        case .top, .bottom:
            .frameResize(position: .top, directions: .all)
        case .leading, .trailing:
            .frameResize(position: .left, directions: .all)
        case .topLeading, .bottomTrailing:
            .frameResize(position: .topLeft, directions: .all)
        case .topTrailing, .bottomLeading:
            .frameResize(position: .topRight, directions: .all)
        }
    }
    
    private static func set(_ newCursor: NSCursor?) {
        cursor = newCursor
        current(default: .crosshair).set()
    }
}

final class CursorHostingView<Content: View>: NSHostingView<Content> {
    private var trackingArea: NSTrackingArea?
    
    private var currentCursor: NSCursor {
        CaptureCursorOverride.current(default: .crosshair)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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
