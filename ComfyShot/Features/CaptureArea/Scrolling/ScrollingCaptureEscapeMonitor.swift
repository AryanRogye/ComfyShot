//
//  ScrollingCaptureEscapeMonitor.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/22/26.
//

import CoreGraphics

/// Listens for Escape while scrolling capture runs in another application.
/// The event tap consumes Escape so it does not also dismiss or modify the
/// application being captured.
@MainActor
final class ScrollingCaptureEscapeMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onEscape: (() -> Void)?

    @discardableResult
    func start(onEscape: @escaping () -> Void) -> Bool {
        stop()
        self.onEscape = onEscape

        let keyDownMask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyDownMask,
            callback: Self.handleEvent,
            userInfo: userInfo
        ), let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            self.onEscape = nil
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        onEscape = nil
    }

    private func receivedEscape() {
        onEscape?()
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<ScrollingCaptureEscapeMonitor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = monitor.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              event.getIntegerValueField(.keyboardEventKeycode) == 53
        else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async {
            monitor.receivedEscape()
        }
        return nil
    }
}
