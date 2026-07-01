//
//  MenuBarCoordinator.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import AppKit
import KeyboardShortcuts

@MainActor
final class MenuBarCoordinator: NSObject {
    
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    
    var onCaptureScreen: (() -> Void)?
    var onCaptureArea: (() -> Void)?
    
    public func start(
        onCaptureScreen: @escaping () -> Void,
        onCaptureArea: @escaping () -> Void
    ) {
        self.onCaptureArea = onCaptureArea
        self.onCaptureScreen = onCaptureScreen
        configureStatusItem()
        configureMenu()
    }
    
    public func stop() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        
        menu = nil
    }
    
    @objc private func quit(_ sender: NSMenuItem) {
    }
    
    @objc private func openSettings(_ sender: NSMenuItem) {
    }
    
    @objc private func captureScreen(_ sender: NSMenuItem) {
        onCaptureScreen?()
    }
    
    @objc private func captureArea(_ sender: NSMenuItem) {
        onCaptureArea?()
    }
}

extension MenuBarCoordinator {
    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let button = statusItem?.button else { return }
        
        if let image = NSImage(named: "ComfyShot") {
            image.isTemplate = true
            button.image = image
        } else {
            let fallbackImage = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "ComfyShot"
            )
            fallbackImage?.isTemplate = true
            button.image = fallbackImage
        }
        
        button.imagePosition = .imageOnly
        button.toolTip = "ComfyShot"
        button.setAccessibilityLabel("ComfyShot")
    }
    
    private func configureMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        menu.addItem(makeMenuItem(
            title: "Capture Screen",
            systemImageName: "display",
            shortcut: KeyboardShortcuts.Name.captureScreen.shortcut,
            action: #selector(captureScreen(_:))
        ))
        
        menu.addItem(makeMenuItem(
            title: "Capture Area",
            systemImageName: "viewfinder",
            shortcut: KeyboardShortcuts.Name.captureArea.shortcut,
            action: #selector(captureArea(_:))
        ))
        
        menu.addItem(.separator())
        
        menu.addItem(makeMenuItem(
            title: "Settings…",
            systemImageName: "gearshape",
            action: #selector(openSettings(_:))
        ))
        
        menu.addItem(makeMenuItem(
            title: "Quit ComfyShot",
            action: #selector(quit(_:))
        ))
        
        self.menu = menu
        statusItem?.menu = menu
    }
}

extension MenuBarCoordinator {
    private func makeMenuItem(
        title: String,
        systemImageName: String? = nil,
        shortcut: KeyboardShortcuts.Shortcut? = nil,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: shortcut?.nsMenuItemKeyEquivalent ?? ""
        )
        
        item.target = self
        item.keyEquivalentModifierMask = shortcut?.modifiers ?? []
        
        if let systemImageName {
            item.image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: title)
            item.image?.isTemplate = true
        }
        
        return item
    }
}
