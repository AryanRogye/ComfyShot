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
    private let screenshotService = ScreenshotService()
    
    private lazy var userImageCoordinator = UserImageCoordinator(
        windowCoordinator: windowCoordinator,
        defaultsManager: defaultsManager
    )

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
        // check for another copy of ComfyShot
        let apps = NSWorkspace.shared.runningApplications
        let pid: pid_t = ProcessInfo.processInfo.processIdentifier
        
        // finds apps that
        if apps.contains(where: { $0.bundleIdentifier == Bundle.main.bundleIdentifier && pid != $0.processIdentifier }) {
            let alert = AlertMaker.makeAlert(
                messageText: "Another ComfyShot Is Running",
                informativeText: "Another copy of ComfyShot is already running. Running multiple copies may cause unexpected behavior.",
                style: .informational,
                buttons: ["Quit", "Terminate Other App", "I Dont Care"])
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                NSApp.terminate(nil)
            case .alertSecondButtonReturn:
                
                for app in apps where app.bundleIdentifier == Bundle.main.bundleIdentifier && app.processIdentifier != pid {
                    app.terminate()
                }
                checkPermissionsThenStart()
            case .alertThirdButtonReturn:
                checkPermissionsThenStart()
            default:
                checkPermissionsThenStart()
            }
        } else {
            checkPermissionsThenStart()
        }
    }
    
    private func checkPermissionsThenStart() {
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
