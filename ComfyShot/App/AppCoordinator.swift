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
    
    private let permissionService = PermissionService()
    private let windowCoordinator = WindowCoordinator()
    private let defaultsManager = DefaultsManager()
    private let menuBarCoordinator = MenuBarCoordinator()
    private let hotkeyCoordinator = HotKeyCoordinator()
    private let userImageCoordinator = UserImageCoordinator()
    private let screenshotService = ScreenshotService()
    
    private lazy var permissionCoordinator = PermissionCoordinator(
        permissionSerivce: permissionService,
        windowCoordinator: windowCoordinator
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
        
        if !permissionService.isAccessibilityEnabled {
            /// show permission
            permissionCoordinator.open()
        }
        
        /// we'll create closures since menuBarCoordinator and hotkeys both use the same thing
        let onCaptureScreen = { [weak self] in
            guard let screen = ScreenHelpers.screenUnderMouse() else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let screenshot = await self.screenshotService.takeScreenshot() {
                    self.userImageCoordinator.addImage(screenshot, to: screen)
                }
            }
        }
        
        let onCaptureArea = { [weak self] in
            guard let self else { return }
            self.userImageCoordinator.hideAll()
            self.captureAreaCoordinator.show()
        }
        
        let onScrollingCapture = { [weak self] in
            guard let self else { return }
            self.userImageCoordinator.hideAll()
            self.captureAreaCoordinator.show(withScrollCapture: true)
        }

        let onOpenSettings = { [weak self] in
            guard let self else { return }
            self.settingsCoordinator.open()
        }
        
        
        menuBarCoordinator.start(
            onCaptureScreen: onCaptureScreen,
            onCaptureArea: onCaptureArea,
            onOpenSettings: onOpenSettings,
            onScrollingCapture: onScrollingCapture,
        )
        
        captureAreaCoordinator.onCaptureImage = { [weak self] image, screen in
            self?.userImageCoordinator.addImage(image, to: screen)
        }
        
        captureAreaCoordinator.onCaptureFinished = { [weak self] in
            self?.userImageCoordinator.showAll()
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
