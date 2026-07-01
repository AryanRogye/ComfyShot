//
//  PermissionService.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import ApplicationServices
import AppKit

@MainActor
@Observable
class PermissionService {
    var isAccessibilityEnabled: Bool = false
    
    var permissionService: PermissionProviding = PermissionFetcherService()

    private var didBecomeActiveObserver: NSObjectProtocol?
    
    private var pollTask: Task<Void, Never>?

    
    init() {
        self.isAccessibilityEnabled = permissionService.getAccessibilityPermissions()
        observeAppActivation()
        if !isAccessibilityEnabled {
            self.requestPermission()
        }
    }

    @MainActor
    deinit {
        pollTask?.cancel()
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }
    
    public func resetAccessibility() throws {
        let process = Process()
        /// tccutil reset Accessibility com.aryanrogye.ComfyTile
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        
        process.arguments = [
            "reset",
            "Accessibility",
            "com.aryanrogye.ComfyTile"
        ]

        try process.run()
    }
    
    public func requestPermission() {
        let status = permissionService.requestAccessibilityPermission()
        permissionService.openPermissionSettings()
        self.isAccessibilityEnabled = status
        startPollingAccessibility()
    }
    public func openPermissionSettings() {
        permissionService.openPermissionSettings()
    }
    
    @MainActor
    private func startPollingAccessibility() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            
            for _ in 1...30 {
                let status = self.permissionService.getAccessibilityPermissions()
                if status != self.isAccessibilityEnabled {
                    self.isAccessibilityEnabled = status
                }
                if status { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func observeAppActivation() {
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            
            DispatchQueue.main.async {
                let status = self.permissionService.getAccessibilityPermissions()
                if status != self.isAccessibilityEnabled {
                    self.isAccessibilityEnabled = status
                }
            }
        }
    }
}

protocol PermissionProviding {
    func getAccessibilityPermissions() -> Bool
    func openPermissionSettings()
    func requestAccessibilityPermission() -> Bool
}


class PermissionFetcherService: PermissionProviding {
    
    func getAccessibilityPermissions() -> Bool {
        AXIsProcessTrusted()
    }
    
    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Request Accessibility Permissions
    func requestAccessibilityPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        
        print(trusted ? "Accessibility permission granted." : "Accessibility permission denied.")
        return trusted
    }
}
