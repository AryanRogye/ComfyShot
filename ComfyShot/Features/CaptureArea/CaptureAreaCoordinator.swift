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
    private let screenshot    : any ScreenshotProviding
    private var overlayScreens: [NSPanel] = []
    private var pendingHide   : DispatchWorkItem?
    
    public var onCaptureImage: ((CGImage, NSScreen) -> Void)?
    public var onCaptureFinished: (() -> Void)?
    
    public init(screenshot: any ScreenshotProviding) {
        self.screenshot = screenshot
    }

    private func setupOverlay() {
        guard !NSScreen.screens.isEmpty else {
            print("Cant SetupOverlay, No screens")
            return
        }

        overlayScreens.forEach { $0.orderOut(nil) }
        overlayScreens = NSScreen.screens.map { screen in
            makeOverlay(for: screen)
        }
    }

    private func makeOverlay(for screen: NSScreen) -> NSPanel {
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
        
        let screenSaverRaw = CGWindowLevelForKey(.screenSaverWindow)
        overlayScreen.level = NSWindow.Level(rawValue: Int(screenSaverRaw))
        
        overlayScreen.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
            
            self.hide()
            
            Task { @MainActor [weak self] in
                guard let self else { return }
                let captureTarget = self.captureTarget(for: rect, on: screen)
                if let image = await screenshot.takeScreenshot(
                    of: captureTarget.screen,
                    croppingTo: captureTarget.rect
                ) {
                    onCaptureImage?(image, captureTarget.screen)
//                    let text = await OCRService.extractText(from: image)
//                    self.showPreviewImage(image, with: text)
                }
                onCaptureFinished?()
            }
        }
        
        model.onExit = { [weak self] in
            guard let self else { return }
            self.hide()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                self?.onCaptureFinished?()
            }
        }

        return overlayScreen
    }
    
    // MARK: - Show Hide Overlay
    public func show() {
        pendingHide?.cancel()
        pendingHide = nil

        guard !NSScreen.screens.isEmpty else {
            print("Can't show, no screens")
            return
        }
        
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
    }
    
    public func hide() {
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

    private func applyCrosshairCursor(to overlayScreen: NSPanel) {
        overlayScreen.acceptsMouseMovedEvents = true

        if let contentView = overlayScreen.contentView {
            overlayScreen.invalidateCursorRects(for: contentView)
        }

        NSCursor.crosshair.set()
    }

    private func overlayForMouse() -> NSPanel? {
        guard let screen = ScreenHelpers.screenUnderMouse() else { return nil }
        return overlayScreens.first { $0.frame == screen.frame }
    }

    private func captureTarget(for overlayRect: CGRect, on screen: NSScreen) -> (screen: NSScreen, rect: CGRect) {
        return (screen, overlayRect.standardized)
    }
}
