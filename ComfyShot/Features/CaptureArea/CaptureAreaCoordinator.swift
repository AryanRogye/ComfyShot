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
    
    private var overlayScreens: [NSPanel] = []
    private var overlayContexts: [OverlayContext] = []
    private var pendingHide   : DispatchWorkItem?

    private var isStartingScrollCapture: Bool = false

    
    public init(defaultsManager: DefaultsManager, screenshot: any ScreenshotProviding) {
        self.defaultsManager = defaultsManager
        self.screenshot = screenshot
    }

    private func setupOverlay() {
        guard !NSScreen.screens.isEmpty else {
            print("Cant SetupOverlay, No screens")
            return
        }

        closeOverlayPanels()
        overlayContexts = NSScreen.screens.map { screen in
            makeOverlayContext(for: screen)
        }
        overlayScreens = overlayContexts.map(\.panel)
    }

    private func makeOverlayContext(for screen: NSScreen) -> OverlayContext {
        let overlayScreen = FocusablePanel(
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

        let model = CaptureAreaModel()
        let view: NSView = CrosshairHostingView(
            rootView: SelectionOverlay(
                model: model
            )
        )
        
        /// Allow hosting view to overflow
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        
        overlayScreen.contentView = view
        // Ensure key events route into SwiftUI hosting view
        overlayScreen.initialFirstResponder = view

        model.capture = { [weak self] rect in
            guard let self else { return }

            let scrollCapture = self.isStartingScrollCapture
            let captureTarget = self.captureTarget(for: rect, on: screen)
            let targetPoint = self.accessibilityTargetPoint(
                for: captureTarget.rect,
                on: captureTarget.screen
            )

            if scrollCapture {
                self.hideImmediatelyForScrollingCapture()
            } else {
                self.hide()
            }

            Task { @MainActor [weak self] in
                guard let self else { return }

                if scrollCapture {
                    try? await Task.sleep(nanoseconds: 300_000_000)

                    let result = await self.scrollingCaptureService.capture(
                        screen: captureTarget.screen,
                        rect: captureTarget.rect,
                        targetPoint: targetPoint
                    )

                    switch result {
                    case .failure:
                        break
                    case .partial(let image, reason: _):
                        self.onCaptureImage?(image, captureTarget.screen)
                    case .success(let image):
                        self.onCaptureImage?(image, captureTarget.screen)
                    }

                    self.onCaptureFinished?()
                } else {
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

        return OverlayContext(
            screen: screen,
            panel: overlayScreen,
            model: model
        )
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

        setupOverlay()
        
        guard let keyOverlay = overlayForMouse() ?? overlayScreens.first else { return }

        NSApp.activate(ignoringOtherApps: true)
        for overlayScreen in overlayScreens {
            if overlayScreen === keyOverlay {
                overlayScreen.makeKeyAndOrderFront(nil)
                overlayScreen.makeFirstResponder(overlayScreen.contentView)
            } else {
                overlayScreen.orderFront(nil)
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
        
        guard !overlayScreens.isEmpty else {
            print("Cant Hide, Overlay is nil")
            return
        }
        
        if overlayScreens.contains(where: \.isVisible) {
            pendingHide?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.overlayScreens.forEach { $0.orderOut(nil) }
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

        closeOverlayPanels()
        NSCursor.arrow.set()
    }

    private func applyCrosshairCursor(to overlayScreen: NSPanel) {
        overlayScreen.acceptsMouseMovedEvents = true

        if let contentView = overlayScreen.contentView {
            overlayScreen.invalidateCursorRects(for: contentView)
        }

        NSCursor.crosshair.set()
    }

    private func closeOverlayPanels() {
        guard !overlayScreens.isEmpty else { return }

        if defaultsManager.captureOverAppleScreenshotUI {
            appleScreenshotInputBridge.stop()
        }
        overlayScreens.forEach {
            $0.orderOut(nil)
            $0.close()
        }
        overlayScreens = []
        overlayContexts = []
    }

    private func overlayForMouse() -> NSPanel? {
        guard let screen = ScreenHelpers.screenUnderMouse() else { return nil }
        return overlayScreens.first { $0.frame == screen.frame }
    }

    private func captureTarget(for overlayRect: CGRect, on screen: NSScreen) -> (screen: NSScreen, rect: CGRect) {
        return (screen, overlayRect.standardized)
    }

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
}
