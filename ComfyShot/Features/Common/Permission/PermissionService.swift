//
//  PermissionService.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import ApplicationServices
import AppKit
import CoreGraphics

@MainActor
@Observable
class PermissionService {
    var isAccessibilityEnabled: Bool = false
    var isScreenRecordingEnabled: Bool = false
    
    var permissionService: PermissionProviding = PermissionFetcherService()
    
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var pollTask: Task<Void, Never>?
    
    init() {
        self.isAccessibilityEnabled = permissionService.getAccessibilityPermissions()
        self.isScreenRecordingEnabled = permissionService.getScreenRecordingPermissions()
        
        observeAppActivation()
    }
    
    @MainActor
    deinit {
        pollTask?.cancel()
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }
    
    // MARK: - Resets
    
    public func resetAccessibility() throws {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        try process.run()
    }
    
    public func resetScreenRecording() throws {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleID]
        try process.run()
    }
    
    // MARK: - Requests
    
    public func requestAccessibilityPermission() {
        let status = permissionService.requestAccessibilityPermission()
        permissionService.openAccessibilitySettings()
        self.isAccessibilityEnabled = status
        startPollingPermissions()
    }
    
    public func requestScreenRecordingPermission() {
        let status = permissionService.requestScreenRecordingPermission()
        permissionService.openScreenRecordingSettings()
        self.isScreenRecordingEnabled = status
        startPollingPermissions()
    }
    
    // MARK: - Observation & Polling
    
    @MainActor
    private func startPollingPermissions() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            
            for _ in 1...30 {
                let accessStatus = self.permissionService.getAccessibilityPermissions()
                let screenStatus = self.permissionService.getScreenRecordingPermissions()
                
                if accessStatus != self.isAccessibilityEnabled {
                    self.isAccessibilityEnabled = accessStatus
                }
                
                if screenStatus != self.isScreenRecordingEnabled {
                    self.isScreenRecordingEnabled = screenStatus
                }
                
                // Stop polling if both are granted
                if accessStatus && screenStatus { break }
                
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
                let accessStatus = self.permissionService.getAccessibilityPermissions()
                let screenStatus = self.permissionService.getScreenRecordingPermissions()
                
                if accessStatus != self.isAccessibilityEnabled {
                    self.isAccessibilityEnabled = accessStatus
                }
                
                if screenStatus != self.isScreenRecordingEnabled {
                    self.isScreenRecordingEnabled = screenStatus
                }
            }
        }
    }
}

protocol PermissionProviding {
    // Accessibility
    func getAccessibilityPermissions() -> Bool
    func openAccessibilitySettings()
    func requestAccessibilityPermission() -> Bool
    
    // Screen Recording
    func getScreenRecordingPermissions() -> Bool
    func openScreenRecordingSettings()
    func requestScreenRecordingPermission() -> Bool
}


class PermissionFetcherService: PermissionProviding {
    
    // MARK: - Accessibility
    
    func getAccessibilityPermissions() -> Bool {
        AXIsProcessTrusted()
    }
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func requestAccessibilityPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        
        print(trusted ? "Accessibility permission granted." : "Accessibility permission denied.")
        return trusted
    }
    
    // MARK: - Screen Recording
    
    func getScreenRecordingPermissions() -> Bool {
        // Checks permission without showing the system prompt
        CGPreflightScreenCaptureAccess()
    }
    
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func requestScreenRecordingPermission() -> Bool {
        let requested = CGRequestScreenCaptureAccess()
        
        let status = CGPreflightScreenCaptureAccess()
        
        print(
            status
            ? "Screen Recording permission granted."
            : "Screen Recording permission denied."
        )
        
        return requested && status
    }
}
