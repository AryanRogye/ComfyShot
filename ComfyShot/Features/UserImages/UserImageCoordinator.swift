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
    
    private let imageSpacing: CGFloat = 12
    

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
    public func add(_ image: CGImage, to screen: NSScreen) {
        guard let display = DisplayIdentity(screen: screen) else { return }
        
        // Use the minimum presentation container for unusually narrow images.
        // UserImageView aspect-fits the pixels inside this size, so the image is
        // never stretched while its hover target and controls remain usable.
        let size = UserImageSizing.containerSizeForImage(image, on: screen)
        let stack = stackForDisplay(display)
        let userImage = UserImage(image: image, size: size)
        stack.addImage(userImage)
        stack.present(
            on: screen,
            padding: UserImageSizing.padding,
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
                padding: UserImageSizing.padding,
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

enum UserImageSizing {
    
    public static let padding: ImageStackPadding = .init(
        leadingPadding: 20,
        trailingPadding: 12,
        topPadding: 12,
        bottomPadding: 12
    )
    
    // Max: 300x360
    private static let maxImageWidth: CGFloat = 300
    private static let maxImageHeight: CGFloat = 360
    
    // Thin captures still need enough room for overlay actions. This floor
    // leaves the leading and trailing controls separated, with space for the
    // controls row to grow, while the image itself remains aspect-fitted.
    private static let minContainerWidth: CGFloat = 240
    private static let minContainerHeight: CGFloat = 160
    
    
    public static func sizeForImage(_ image: CGImage, on screen: NSScreen) -> NSSize {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let availableHeight = max(1, screen.visibleFrame.height - padding.topPadding * 2)
        let heightLimit = min(maxImageHeight, availableHeight * 0.45)
        
        // Image only ever scales DOWN to fit the max box — never stretched up.
        let scale = min(1, maxImageWidth / imageWidth, heightLimit / imageHeight)
        
        return NSSize(
            width: max(1, imageWidth * scale),
            height: max(1, imageHeight * scale)
        )
    }
    
    /// Container size: the box the image sits in, which enforces the mins.
    /// The image gets centered inside this — it does NOT get scaled to fill it.
    public static func containerSizeForImage(_ image: CGImage, on screen: NSScreen) -> NSSize {
        let imageSize = sizeForImage(image, on: screen)
        return NSSize(
            width: max(minContainerWidth, imageSize.width),
            height: max(minContainerHeight, imageSize.height)
        )
    }
}
