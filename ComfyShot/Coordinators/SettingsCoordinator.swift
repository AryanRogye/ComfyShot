//
//  SettingsCoordinator.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import Foundation
import AppKit

final class SettingsCoordinator {
    
    let windowCoordinator: WindowCoordinator
    let defaultsManager: DefaultsManager
    let id = UUID().uuidString
    
    init(
        windowCoordinator: WindowCoordinator,
        defaultsManager: DefaultsManager
    ) {
        self.windowCoordinator = windowCoordinator
        self.defaultsManager = defaultsManager
    }
    
    public func open() {
        
        // show icon on open
        NSApplication.shared.setActivationPolicy(.regular)
        
        let window = self.windowCoordinator.showWindow(
            id: id,
            title: "Settings",
            content: SettingsView(defaultsManager: defaultsManager),
            onClose: {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        )
        
        window.orderFrontRegardless()
        
        DispatchQueue.main.async {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}
