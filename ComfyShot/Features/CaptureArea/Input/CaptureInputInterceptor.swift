//
//  CaptureInputInterceptor.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Owns keyboard and pointer input during an isolated area capture.
///
/// The event tap consumes input before the Dock or foreground application sees
/// it. Their last hover, menu, or pressed state therefore remains onscreen.
/// Because consumed movement cannot move the hardware cursor, this type builds a
/// virtual position from raw mouse deltas and sends that position to the UI.
///
/// Event Mask: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved, .scrollWheel, .keyDown]
///
/// The event tap is attached to the main run loop.
///
/// subscribed event happens
///          ↓
/// eventTapCallback
///          ↓
/// handle(_ event: CGEvent, type: CGEventType)
///
/// Events outside the mask are never sent to our callback.
final class CaptureInputInterceptor {
    // MARK: - Capture Actions
    var mouseDown: ((CGPoint) -> Void)?
    var mouseDragged: ((CGPoint) -> Void)?
    var mouseUp: ((CGPoint) -> Void)?
    var mouseMoved: ((CGPoint) -> Void)?
    var cancel: (() -> Void)?
    var capture: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Some devices report moved events during a drag, so drag state is tracked
    /// independently from the incoming Core Graphics event type.
    private var isDragging = false

    /// This uses AppKit's global, bottom-left screen coordinate system.
    private var virtualMouseLocation: CGPoint = .zero

    lazy var cursorController = SystemCursorController(
        onGetVirtualMouseLocation: { [weak self] in
            self?.virtualMouseLocation ?? .zero
        },
        onGetIsRunning: { [weak self] in
            self?.isRunning ?? false
        }
    )

    var isRunning: Bool {
        eventTap != nil
    }
}

// MARK: - Public API's
extension CaptureInputInterceptor {
    /// Installs the HID event tap. `false` lets the coordinator use ordinary
    /// AppKit input when system permission or tap creation is unavailable.
    public func start(
        mouseDown: @escaping (CGPoint) -> Void,
        mouseDragged: @escaping (CGPoint) -> Void,
        mouseUp: @escaping (CGPoint) -> Void,
        mouseMoved: @escaping (CGPoint) -> Void,
        cancel: @escaping () -> Void,
        capture: @escaping () -> Void,
    ) -> Bool {
        stop()
        self.mouseDown = mouseDown
        self.mouseDragged = mouseDragged
        self.mouseUp = mouseUp
        self.mouseMoved = mouseMoved
        self.cancel = cancel
        self.capture = capture
        self.virtualMouseLocation = NSEvent.mouseLocation

        /// Lets us intercept mouse/keyboard input
        /// before any apps reacts to it
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            /// Masks that we want to capture
            eventsOfInterest: Self.eventMask(
                for: [
                    .leftMouseDown,
                    .leftMouseDragged,
                    .leftMouseUp,
                    .mouseMoved,
                    .scrollWheel,
                    .keyDown
                ]
            ),
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            clearHandlers()
            return false
        }

        return installEventTapOnMainRunLoop(eventTap: eventTap)
    }

    // MARK: - Stop
    /// Tears down interception and restores the real pointer. This is idempotent
    /// because several capture completion and cancellation paths call it.
    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        clearHandlers()
        isDragging = false
        cursorController.showSystemCursor()
    }

    /// Hides the real pointer after all capture panels are onscreen. Panel
    /// presentation can install a cursor rectangle, so calling this sooner races
    /// with AppKit and makes the hardware cursor reappear.
    public func hideSystemCursor() {
        cursorController.hideSystemCursor()
    }

}

// MARK: - Event Handling
extension CaptureInputInterceptor {
    /// Converts intercepted events into capture actions. Returning `nil` removes
    /// the event before the underlying application or Dock can react to it.
    private func handle(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        switch type {
        case .leftMouseDown:
            isDragging = true
            let point = virtualMouseLocation
            mouseDown?(point)
            return nil

        case .leftMouseDragged:
            let point = advanceVirtualMouse(using: event)
            mouseDragged?(point)
            return nil

        case .mouseMoved:
            let point = advanceVirtualMouse(using: event)
            if isDragging {
                mouseDragged?(point)
            } else {
                mouseMoved?(point)
            }
            return nil

        case .leftMouseUp:
            isDragging = false
            let point = virtualMouseLocation
            mouseUp?(point)
            return nil

        case .scrollWheel:
            /// Scrolling would mutate the frozen content beneath the overlay.
            return nil

        case .keyDown:
            return handleKeyDown(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Handles Enter and Escape locally because non-key panels cannot receive
    /// keyboard commands. Other keys are consumed to preserve transient UI.
    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case 36, 76:
            capture?()
        case 53:
            cancel?()
        default:
            break
        }
        return nil
    }

    func clearHandlers() {
        self.mouseDown = nil
        self.mouseDragged = nil
        self.mouseUp = nil
        self.mouseMoved = nil
        self.cancel = nil
        self.capture = nil
    }
}

// MARK: - Virtual Pointer
extension CaptureInputInterceptor {
    /// Builds a virtual AppKit position from raw HID deltas. HID Y grows downward,
    /// while AppKit global Y grows upward, so the Y delta is inverted.
    private func advanceVirtualMouse(using event: CGEvent) -> CGPoint {
        let deltaX = CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
        let deltaY = CGFloat(event.getIntegerValueField(.mouseEventDeltaY))
        let proposedPoint = CGPoint(
            x: virtualMouseLocation.x + deltaX,
            y: virtualMouseLocation.y - deltaY
        )

        virtualMouseLocation = Self.pointConstrainedToScreens(proposedPoint)
        return virtualMouseLocation
    }

    /// Keeps the virtual pointer on the nearest real display when a multi-display
    /// arrangement contains gaps or the pointer reaches an outer screen edge.
    private static func pointConstrainedToScreens(_ point: CGPoint) -> CGPoint {
        let frames = NSScreen.screens.map(\.frame)
        guard !frames.isEmpty else { return point }
        if frames.contains(where: { $0.contains(point) }) { return point }

        return frames
            .map { frame in
                CGPoint(
                    x: min(max(point.x, frame.minX), frame.maxX - 0.001),
                    y: min(max(point.y, frame.minY), frame.maxY - 0.001)
                )
            }
            .min {
                hypot($0.x - point.x, $0.y - point.y)
                    < hypot($1.x - point.x, $1.y - point.y)
            } ?? point
    }
}

// MARK: - Event Tap Callback
extension CaptureInputInterceptor {
    /// Core Graphics calls this C-compatible closure for each subscribed event.
    /// It recovers the Swift owner and re-enables taps disabled by a timeout.
    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let interceptor = Unmanaged<CaptureInputInterceptor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = interceptor.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        return interceptor.handle(event, type: type)
    }

    /// Core Graphics stores subscriptions as bits indexed by event type.
    private static func eventMask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }
}

// MARK: - Loop Creation
extension CaptureInputInterceptor {
    private func installEventTapOnMainRunLoop(eventTap: CFMachPort) -> Bool {

        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            clearHandlers()
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }
}
