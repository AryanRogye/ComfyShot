//
//  UserImageCoordinator.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import AppKit

@MainActor
final class UserImageCoordinator {
    
    /// Active image stacks keyed by physical display ID. Each stack owns at most one panel.
    private var stacksByDisplay: [DisplayIdentity: DisplayImageStack] = [:]
    private var stacksAreHidden = false
    
    private var screenParametersObserver: NSObjectProtocol?
    
    private let padding: ImageStackPadding = .init(
        leadingPadding: 20,
        trailingPadding: 12,
        topPadding: 12,
        bottomPadding: 12
    )
    private let imageSpacing: CGFloat = 12
    private let maxImageWidth: CGFloat = 300
    private let maxImageHeight: CGFloat = 360
    
    init() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleScreenConfigurationChanged()
            }
        }
    }
    
    @MainActor
    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        
        stacksByDisplay.values.forEach { $0.closePanel() }
    }
    
    /// function adds the image, and displays the panel onto the given screen
    public func addImage(_ image: CGImage, to screen: NSScreen) {
        guard let display = DisplayIdentity(screen: screen) else { return }
        
        let size = sizeForImage(image, on: screen)
        let stack = stackForDisplay(display)
        let userImage = UserImage(image: image, size: size)
        stack.addImage(userImage)
        stack.present(
            on: screen,
            padding: padding,
            imageSpacing: imageSpacing
        )
        
        if stacksAreHidden {
            stack.hide()
        }
    }
    
    /// Closes all panels on a screen and resets its stack pointer.
    public func reset(for screen: NSScreen) {
        guard let display = DisplayIdentity(screen: screen) else { return }
        
        stacksByDisplay[display]?.closePanel()
        stacksByDisplay[display] = nil
    }

    public func hideAll() {
        stacksAreHidden = true
        stacksByDisplay.values.forEach { $0.hide() }
    }

    public func showAll() {
        stacksAreHidden = false
        stacksByDisplay.values.forEach { $0.show() }
    }

    /// Picks a display size from the raw CGImage dimensions, preserving aspect
    /// ratio while keeping tall captures from dominating the screen.
    private func sizeForImage(_ image: CGImage, on screen: NSScreen) -> NSSize {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let availableHeight = max(1, screen.visibleFrame.height - padding.topPadding * 2)
        let heightLimit = min(maxImageHeight, availableHeight * 0.45)
        let scale = min(1, maxImageWidth / imageWidth, heightLimit / imageHeight)
        
        return NSSize(
            width: max(1, imageWidth * scale),
            height: max(1, imageHeight * scale)
        )
    }
    
    /// Function retreives a stack for a `DisplayIdentity` if doesnt exist,
    /// we create it and return the newly created stack
    private func stackForDisplay(_ display: DisplayIdentity) -> DisplayImageStack {
        if let stack = stacksByDisplay[display] {
            return stack
        }
        
        let stack = DisplayImageStack()
        stacksByDisplay[display] = stack
        return stack
    }
    
    private func handleScreenConfigurationChanged() {
        var activeDisplays = Set<DisplayIdentity>()
        
        for screen in NSScreen.screens {
            // create a displayID, if success add it to the activeDisplays
            guard let display = DisplayIdentity(screen: screen) else { continue }
            activeDisplays.insert(display)
            
            // see if we have a currentStack for the display, and not empty
            // if is empty we just keep going on to the next screen
            guard let stack = stacksByDisplay[display], !stack.model.images.isEmpty else {
                continue
            }
            
            // if stack for display is not empty, we just replace it quickly
            stack.present(
                on: screen,
                padding: padding,
                imageSpacing: imageSpacing
            )
            
            if stacksAreHidden {
                stack.hide()
            }
        }
        
        // remove panels if we need to, this would only happen if we lose a display/NSScreen
        for (display, stack) in stacksByDisplay where !activeDisplays.contains(display) {
            stack.closePanel()
        }
    }
}
