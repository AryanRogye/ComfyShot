//
//  AppDelegate.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var appCoordinator: AppCoordinator?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard !ProcessInfo.isSwiftUIPreview else { return }
        
        appCoordinator = AppCoordinator()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        return true
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        appCoordinator?.stop()
        appCoordinator = nil
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
