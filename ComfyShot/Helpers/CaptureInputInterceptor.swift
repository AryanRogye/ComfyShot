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

final class CaptureInputInterceptor {
    struct Handlers {
        var mouseDown: (CGPoint) -> Void
        var mouseDragged: (CGPoint) -> Void
        var mouseUp: (CGPoint) -> Void
        var cancel: () -> Void
        var capture: () -> Void
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handlers: Handlers?
    private var isDragging = false

    var isRunning: Bool {
        eventTap != nil
    }

    func start(handlers: Handlers) -> Bool {
        stop()

        self.handlers = handlers

        let accessibilityOptions = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(accessibilityOptions)

        let eventMask = Self.eventMask(
            for: [
                .leftMouseDown,
                .leftMouseDragged,
                .leftMouseUp,
                .mouseMoved,
                .keyDown
            ]
        )

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.handleEvent,
            userInfo: userInfo
        ) else {
            self.handlers = nil
            return false
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            self.handlers = nil
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
        handlers = nil
        isDragging = false
    }

    private func dispatch(_ work: @escaping (Handlers) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let handlers = self?.handlers else { return }
            work(handlers)
        }
    }

    private func handle(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        switch type {
        case .leftMouseDown:
            isDragging = true
            let point = Self.appKitPoint(fromQuartzPoint: event.location)
            dispatch { $0.mouseDown(point) }
            return nil

        case .leftMouseDragged:
            let point = Self.appKitPoint(fromQuartzPoint: event.location)
            dispatch { $0.mouseDragged(point) }
            return nil

        case .mouseMoved:
            guard isDragging else {
                return Unmanaged.passUnretained(event)
            }

            let point = Self.appKitPoint(fromQuartzPoint: event.location)
            dispatch { $0.mouseDragged(point) }
            return nil

        case .leftMouseUp:
            isDragging = false
            let point = Self.appKitPoint(fromQuartzPoint: event.location)
            dispatch { $0.mouseUp(point) }
            return nil

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            switch keyCode {
            case 36, 76:
                dispatch { $0.capture() }
                return nil

            case 53:
                dispatch { $0.cancel() }
                return nil

            default:
                return nil
            }

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard type != .tapDisabledByTimeout, type != .tapDisabledByUserInput else {
            if let userInfo {
                let interceptor = Unmanaged<CaptureInputInterceptor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                if let eventTap = interceptor.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
            }

            return Unmanaged.passUnretained(event)
        }

        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let interceptor = Unmanaged<CaptureInputInterceptor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return interceptor.handle(event, type: type)
    }

    private static func eventMask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }

    private static func appKitPoint(fromQuartzPoint point: CGPoint) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let displayID = screen.displayID else { return false }
            return CGDisplayBounds(displayID).contains(point)
        }), let displayID = screen.displayID else {
            return NSEvent.mouseLocation
        }

        let quartzFrame = CGDisplayBounds(displayID)
        return CGPoint(
            x: screen.frame.minX + point.x - quartzFrame.minX,
            y: screen.frame.maxY - (point.y - quartzFrame.minY)
        )
    }
}
