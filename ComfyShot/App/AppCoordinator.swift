//
//  AppCoordinator.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import AppKit
import SnapCore

@MainActor
class AppCoordinator {
    
    private lazy var windowCoordinator = WindowCoordinator()
    
    private let permissionService = PermissionService()
    private let updateController = UpdateController()

    private let defaultsManager = DefaultsManager()
    private let menuBarCoordinator = MenuBarCoordinator()
    private let hotkeyCoordinator = HotKeyCoordinator()
    private let userImageCoordinator = UserImageCoordinator()
    private let screenshotService = ScreenshotService()
    
    private lazy var permissionCoordinator = PermissionCoordinator(
        permissionService: permissionService,
        windowCoordinator: windowCoordinator,
        onClose: { [weak self] in
            guard let self else { return }
            self.start()
        }
    )
    
    private lazy var captureAreaCoordinator = CaptureAreaCoordinator(
        defaultsManager: defaultsManager,
        screenshot: screenshotService
    )
    private lazy var settingsCoordinator = SettingsCoordinator(
        windowCoordinator: windowCoordinator,
        defaultsManager: defaultsManager
    )
    
    init() {
        if !permissionService.isAccessibilityEnabled || !permissionService.isScreenRecordingEnabled {
            permissionCoordinator.open()
        } else {
            start()
        }
    }
    
    var didStart = false
    
    private func start() {
        if didStart { return }
        didStart = true
        /// we'll create closures since menuBarCoordinator and hotkeys both use the same thing
        
        /// Capture Screen captures the entire screen where the users mouse is
        let onCaptureScreen = { [weak self] in
            guard let screen = ScreenHelpers.screenUnderMouse() else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let screenshot = await self.screenshotService.takeScreenshot() {
                    self.userImageCoordinator.add(screenshot, to: screen)
                }
            }
        }
        
        /// Capture Area triggers a box area that the user can select to decide where the screenshot will be
        let onCaptureArea = { [weak self] in
            guard let self else { return }
            self.userImageCoordinator.hideAll()
            self.captureAreaCoordinator.show()
        }
        
        /// Scrolling Capture to capture scrolling in a area
        let onScrollingCapture = { [weak self] in
            guard let self else { return }
            self.userImageCoordinator.hideAll()
            self.captureAreaCoordinator.show(withScrollCapture: true)
        }
        
        /// Open Settings
        let onOpenSettings = { [weak self] in
            guard let self else { return }
            self.settingsCoordinator.open()
        }
        
        
        menuBarCoordinator.start(
            updaterVM: updateController.updaterVM,
            updateController: updateController,
            onCaptureScreen: onCaptureScreen,
            onCaptureArea: onCaptureArea,
            onOpenSettings: onOpenSettings,
            onScrollingCapture: onScrollingCapture,
        )
        
        captureAreaCoordinator.onCaptureImage = { [weak self] image, screen in
            guard let self else { return }
            self.userImageCoordinator.add(image, to: screen)
        }
        
        captureAreaCoordinator.onCaptureFinished = { [weak self] in
            guard let self else { return }
            self.userImageCoordinator.showAll()
        }
        
        hotkeyCoordinator.start(
            onCaptureScreen: onCaptureScreen,
            onCaptureArea: onCaptureArea,
            onScrollingCapture: onScrollingCapture
        )
    }

    public func stop() {
        menuBarCoordinator.stop()
    }
}
