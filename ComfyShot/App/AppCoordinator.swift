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
    
    private let menuBarCoordinator = MenuBarCoordinator()
    private let hotkeyCoordinator = HotKeyCoordinator()
    private let userImageCoordinator = UserImageCoordinator()
    private let screenshotService = ScreenshotService()
    
    private lazy var captureAreaCoordinator = CaptureAreaCoordinator(screenshot: screenshotService)
    
    init() {
        
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
        
        menuBarCoordinator.start(
            onCaptureScreen: onCaptureScreen,
            onCaptureArea: onCaptureArea
        )
        
        captureAreaCoordinator.onCaptureImage = { [weak self] image, screen in
            self?.userImageCoordinator.addImage(image, to: screen)
        }
        
        captureAreaCoordinator.onCaptureFinished = { [weak self] in
            self?.userImageCoordinator.showAll()
        }
        
        hotkeyCoordinator.start(
            onCaptureScreen: onCaptureScreen,
            onCaptureArea: onCaptureArea
        )
    }

    public func stop() {
        menuBarCoordinator.stop()
    }
}
