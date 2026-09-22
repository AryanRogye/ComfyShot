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
/// The session event tap consumes input before the Dock or foreground application
/// sees it, after WindowServer has moved the system cursor. Their last hover,
/// menu, or pressed state therefore remains onscreen.
///
/// Event Mask: pointer buttons, movement, scrolling, and key down.
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
    var clearSelection: (() -> Void)?
    var capture: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Some devices report moved events during a drag, so drag state is tracked
    /// independently from the incoming Core Graphics event type.
    private var isDragging = false

    var isRunning: Bool {
        eventTap != nil
    }
}

// MARK: - Public API's
extension CaptureInputInterceptor {
    /// Installs the session event tap. `false` lets the coordinator use ordinary
    /// AppKit input when system permission or tap creation is unavailable.
    public func start(
        mouseDown: @escaping (CGPoint) -> Void,
        mouseDragged: @escaping (CGPoint) -> Void,
        mouseUp: @escaping (CGPoint) -> Void,
        mouseMoved: @escaping (CGPoint) -> Void,
        cancel: @escaping () -> Void,
        clearSelection: @escaping () -> Void,
        capture: @escaping () -> Void,
    ) -> Bool {
        stop()
        self.mouseDown = mouseDown
        self.mouseDragged = mouseDragged
        self.clearSelection = clearSelection
        self.mouseUp = mouseUp
        self.mouseMoved = mouseMoved
        self.cancel = cancel
        self.capture = capture
        /// Lets us intercept mouse/keyboard input
        /// before any apps reacts to it
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            /// Masks that we want to capture
            eventsOfInterest: Self.eventMask(
                for: [
                    .leftMouseDown,
                    .leftMouseDragged,
                    .leftMouseUp,
                    .rightMouseDown,
                    .rightMouseDragged,
                    .rightMouseUp,
                    .otherMouseDown,
                    .otherMouseDragged,
                    .otherMouseUp,
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
    /// Tears down interception. This is idempotent
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
            let point = event.location.appKitPoint
            mouseDown?(point)
            return nil

        case .leftMouseDragged:
            let point = event.location.appKitPoint
            mouseDragged?(point)
            return nil

        case .mouseMoved:
            let point = event.location.appKitPoint
            if isDragging {
                mouseDragged?(point)
            } else {
                mouseMoved?(point)
            }
            return nil

        case .leftMouseUp:
            isDragging = false
            let point = event.location.appKitPoint
            mouseUp?(point)
            return nil

        case .scrollWheel:
            /// Scrolling would mutate the frozen content beneath the overlay.
            return nil

        case .rightMouseDown, .rightMouseDragged, .rightMouseUp,
             .otherMouseDown, .otherMouseDragged, .otherMouseUp:
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
        case 8:
            clearSelection?()
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
        self.clearSelection = nil
        self.capture = nil
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
