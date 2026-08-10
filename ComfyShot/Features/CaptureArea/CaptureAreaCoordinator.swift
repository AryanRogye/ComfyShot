//
//  CaptureAreaCoordinator.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import AppKit
import SnapCore
import SwiftUI

final class CaptureAreaCoordinator {
    
    private let defaultsManager: DefaultsManager
    private let screenshot    : any ScreenshotProviding

    /// set by `AppCoordinator`
    public var onCaptureImage: ((CGImage, NSScreen) -> Void)?
    public var onCaptureFinished: (() -> Void)?

    private lazy var appleScreenshotInputBridge = AppleScreenshotInputBridge()
    private lazy var scrollingCaptureService = ScrollingCaptureService(
        screenshot: screenshot
    )
    private let scrollingCaptureEscapeMonitor = ScrollingCaptureEscapeMonitor()
    private var scrollingCaptureTask: Task<Void, Never>?
    private var scrollingCaptureID: UUID?
    
    private var overlayContexts: [OverlayContext] = []
    private var models: [CGDirectDisplayID: CaptureAreaModel] = [:]
    private var pendingHide   : DispatchWorkItem?

    private var isStartingScrollCapture: Bool = false

    
    public init(defaultsManager: DefaultsManager, screenshot: any ScreenshotProviding) {
        self.defaultsManager = defaultsManager
        self.screenshot = screenshot
    }

    private func model(for screen: NSScreen) -> CaptureAreaModel {
        guard let displayID = screen.displayID else {
            return CaptureAreaModel()
        }

        if let model = models[displayID] {
            return model
        }

        let model = CaptureAreaModel()
        models[displayID] = model
        return model
    }

    // MARK: - Show Hide Overlay
    public func show(withScrollCapture: Bool = false) {
        pendingHide?.cancel()
        pendingHide = nil
        
        guard !NSScreen.screens.isEmpty else {
            print("Can't show, no screens")
            return
        }
        
        isStartingScrollCapture = withScrollCapture

        // setup all the overlays
        setupOverlaysForAllScreens()
        
        guard let keyOverlay = overlayForMouse() ?? overlayContexts.map(\.panel).first else { return }

        for overlayScreen in overlayContexts.map(\.panel) {
            if overlayScreen === keyOverlay {
                overlayScreen.orderFrontRegardless()
                overlayScreen.makeKey()
                overlayScreen.makeFirstResponder(overlayScreen.contentView)
            } else {
                overlayScreen.orderFrontRegardless()
            }
            overlayScreen.ignoresMouseEvents = false
            applyCrosshairCursor(to: overlayScreen)
        }
        
        if defaultsManager.captureOverAppleScreenshotUI {
            appleScreenshotInputBridge.startIfNeeded(
                contexts: overlayContexts,
                onCancel: { [weak self] in
                    self?.hide()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                        self?.onCaptureFinished?()
                    }
                }
            )
        }
    }
    
    public func hide() {
        isStartingScrollCapture = false
        if defaultsManager.captureOverAppleScreenshotUI {
            appleScreenshotInputBridge.stop()
        }
        
        guard !overlayContexts.isEmpty else {
            print("Cant Hide, Overlay is nil")
            return
        }
        
        if overlayContexts.map(\.panel).contains(where: \.isVisible) {
            pendingHide?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.overlayContexts.map(\.panel).forEach { $0.orderOut(nil) }
                self.pendingHide = nil
                
                NSCursor.arrow.set()
            }
            pendingHide = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
    }

    private func hideImmediatelyForScrollingCapture() {
        pendingHide?.cancel()
        pendingHide = nil
        isStartingScrollCapture = false

        closeAndResetOverlayPanels()
        NSCursor.arrow.set()
    }

    private func applyCrosshairCursor(to overlayScreen: NSPanel) {
        overlayScreen.acceptsMouseMovedEvents = true

        if let contentView = overlayScreen.contentView {
            overlayScreen.invalidateCursorRects(for: contentView)
        }

        NSCursor.crosshair.set()
    }
    
    private func overlayForMouse() -> NSPanel? {
        guard let screen = ScreenHelpers.screenUnderMouse() else { return nil }
        return overlayContexts.map(\.panel).first { $0.frame == screen.frame }
    }

    private func captureTarget(for overlayRect: CGRect, on screen: NSScreen) -> (screen: NSScreen, rect: CGRect) {
        return (screen, overlayRect.standardized)
    }
}

extension CaptureAreaCoordinator {
    
    internal func setupOverlaysForAllScreens() {
        guard !NSScreen.screens.isEmpty else {
            print("Cant SetupOverlay, No screens")
            return
        }
        
        closeAndResetOverlayPanels()
        removeDisconnectedDisplayModels()
        createOverlayContexts()
    }
    
    private func createOverlayContexts() {
        overlayContexts = NSScreen.screens.map { screen in
            makeOverlayContext(for: screen)
        }
    }
    
    private func removeDisconnectedDisplayModels() {
        let connectedDisplayIDs = Set(NSScreen.screens.compactMap(\.displayID))
        models = models.filter { connectedDisplayIDs.contains($0.key) }
    }
    
    private func closeAndResetOverlayPanels() {
        guard !overlayContexts.isEmpty else { return }

        if defaultsManager.captureOverAppleScreenshotUI {
            appleScreenshotInputBridge.stop()
        }
        overlayContexts.map(\.panel).forEach {
            $0.orderOut(nil)
            $0.close()
        }
        overlayContexts = []
    }
    
    private func makeOverlayContext(for screen: NSScreen) -> OverlayContext {
        // create a NSPanel to cover the screen
        let overlayScreen = createPanel(for: screen)
        // create the model that belongs to the view
        let model = createModel(for: screen)
        
        let view: NSView = CursorHostingView(
            rootView: SelectionOverlay(
                model: model,
                defaultsManager: defaultsManager
            )
        )
        
        // basic config
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        
        overlayScreen.contentView = view
        overlayScreen.initialFirstResponder = view
        
        return OverlayContext(
            screen: screen,
            panel: overlayScreen,
            model: model
        )
    }
    
    private func createModel(for screen: NSScreen) -> CaptureAreaModel {
        let model = model(for: screen)
        model.keepSelectionInBoundsIfNeeded(
            to: CGRect(origin: .zero, size: screen.frame.size)
        )

        model.capture = { [weak self] rect in
            guard let self else { return }
            
            let scrollCapture = self.isStartingScrollCapture
            let captureTarget = self.captureTarget(for: rect, on: screen)
            let targetPoint = accessibilityTargetPoint(
                for: captureTarget.rect,
                on: captureTarget.screen
            )
            
            if scrollCapture {
                self.hideImmediatelyForScrollingCapture()
            } else {
                self.hide()
            }
            
            if scrollCapture {
                self.startScrollingCapture(
                    screen: captureTarget.screen,
                    rect: captureTarget.rect,
                    targetPoint: targetPoint
                )
            } else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let image = await self.screenshot.takeScreenshot(
                        of: captureTarget.screen,
                        croppingTo: captureTarget.rect
                    ) {
                        self.onCaptureImage?(image, captureTarget.screen)
                    }
                    self.onCaptureFinished?()
                }
            }
        }
        
        model.onSelectionBegan = { [weak self, weak model] in
            guard let self, let model else { return }
            
            self.overlayContexts
                .filter { $0.model !== model }
                .forEach { $0.model.clearSelection() }
        }
        
        model.onExit = { [weak self] in
            guard let self else { return }
            self.hide()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                self?.onCaptureFinished?()
            }
        }
        return model
    }

    private func startScrollingCapture(
        screen: NSScreen,
        rect: CGRect,
        targetPoint: CGPoint
    ) {
        scrollingCaptureTask?.cancel()

        let captureID = UUID()
        scrollingCaptureID = captureID

        scrollingCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.finishScrollingCapture(id: captureID)
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let result = await self.scrollingCaptureService.capture(
                screen: screen,
                rect: rect,
                targetPoint: targetPoint
            )

            guard self.scrollingCaptureID == captureID else { return }
            switch result {
            case .failure:
                break
            case .partial(let image, reason: _), .success(let image):
                self.onCaptureImage?(image, screen)
            }
        }

        let monitorStarted = scrollingCaptureEscapeMonitor.start { [weak self] in
            self?.scrollingCaptureTask?.cancel()
        }
        if !monitorStarted {
            print("Scrolling capture Escape monitor could not start. Accessibility/Input Monitoring permission may be required.")
        }
    }

    private func finishScrollingCapture(id: UUID) {
        guard scrollingCaptureID == id else { return }

        scrollingCaptureEscapeMonitor.stop()
        scrollingCaptureTask = nil
        scrollingCaptureID = nil
        onCaptureFinished?()
    }
}

/// Create NSPanel
private func createPanel(for screen: NSScreen) -> NSPanel {
    let overlayScreen = ActiveAppearancePanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    overlayScreen.setFrame(screen.frame, display: true)
    /// Allow content to draw outside panel bounds
    overlayScreen.contentView?.wantsLayer = true
    
    overlayScreen.registerForDraggedTypes([.fileURL])
    overlayScreen.title = ""
    overlayScreen.acceptsMouseMovedEvents = true
    
    overlayScreen.level = NSWindow.Level(rawValue: Int(1600))
    overlayScreen.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    overlayScreen.isFloatingPanel = true
    overlayScreen.hidesOnDeactivate = false
    overlayScreen.isMovableByWindowBackground = false
    overlayScreen.backgroundColor = .clear
    overlayScreen.isOpaque = false
    overlayScreen.hasShadow = false
    return overlayScreen
}

/// converting a rectangle that exists in the overlay’s local coordinate space
/// into a global screen point that Accessibility can use
private func accessibilityTargetPoint(for overlayRect: CGRect, on screen: NSScreen) -> CGPoint {
    let rect = overlayRect.standardized
    
    guard let displayID = screen.displayID else {
        return CGPoint(
            x: screen.frame.minX + rect.midX,
            y: screen.frame.minY + rect.midY
        )
    }
    
    let displayBounds = CGDisplayBounds(displayID)
    return CGPoint(
        x: displayBounds.minX + rect.midX,
        y: displayBounds.minY + rect.midY
    )
}

/// Listens for Escape while scrolling capture runs in another application.
/// The event tap consumes Escape so it does not also dismiss or modify the
/// application being captured.
@MainActor
private final class ScrollingCaptureEscapeMonitor {
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
