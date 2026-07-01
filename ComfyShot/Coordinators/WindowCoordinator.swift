//
//  WindowCoordinator.swift
//
//  Copyright (c) 2024–2025 Aryan Rogye
//  Licensed under the MIT License
//

import AppKit
import SwiftUI

/// Window Coordinator manages the lifecycle of multiple windows in the application.
/// - Parameters:
///   - windows: windowID -> NSWindow, each ids NSWindow
///   - onOpenAction: windowID -> action(), when the window opens this function is called
///   - onCloseAction: windowID -> action(), when the window is closed this function is called
///   - onBlueAction: windowID -> action(), when the window is not in focus function is called
///   - onResizeAction: windowID -> action(isResizing), called continuously while the window is being resized; `isResizing` is `true` when a resize is in progress and `false` when it has ended
///   - delegates: windowID -> WindowDelegates, each ids WindowDelegate
class WindowCoordinator {
    
    private var windows : [String: NSWindow] = [:]
    
    private var onOpenAction : [String: (() -> Void)] = [:]
    private var onCloseAction : [String: (() -> Void)] = [:]
    private var onBlurAction: [String: (() -> Void)] = [:]
    private var onResizeAction: [String: ((Bool) -> Void)] = [:]
    
    private var delegates: [String: WindowDelegate] = [:]
    
    deinit {
        // Clean up all windows when the coordinator is deinitialized
        for window in windows.values {
            DispatchQueue.main.async {
                window.close()
            }
        }
        windows.removeAll()
    }
}

/// A per-window delegate that forwards `NSWindowDelegate` lifecycle events to the `WindowCoordinator`.
///
/// Each managed window owns one `WindowDelegate`. The delegate holds a weak reference to the
/// coordinator to avoid a retain cycle, since the coordinator owns the delegates dictionary.
fileprivate class WindowDelegate: NSObject, NSWindowDelegate {
    
    /// The ID of the window this delegate is managing, used to route events in the coordinator.
    let id: String
    
    /// Weak reference to the owning coordinator to avoid a retain cycle.
    weak var coordinator: WindowCoordinator?
    
    init(id: String, coordinator: WindowCoordinator) {
        self.id = id
        self.coordinator = coordinator
    }
    
    /// Fires when the window loses key status — maps to `onBlur`.
    func windowDidResignKey(_ notification: Notification) {
        coordinator?.handleWindowBlur(id: id)
    }
    
    /// Fires when the window becomes key — maps to `onOpen`.
    func windowDidBecomeKey(_ notification: Notification) {
        coordinator?.handleWindowOpen(id: id)
    }
    
    /// Fires just before the window closes — maps to `onClose`.
    func windowWillClose(_ notification: Notification) {
        coordinator?.handleWindowClose(id: id)
    }
    
    /// Fires when the user begins a live resize — maps to `onResize(true)`.
    func windowWillStartLiveResize(_ notification: Notification) {
        coordinator?.handleWindowResize(id: id, isResizing: true)
    }
    
    /// Fires when the live resize ends — maps to `onResize(false)`.
    func windowDidEndLiveResize(_ notification: Notification) {
        coordinator?.handleWindowResize(id: id, isResizing: false)
    }
}

extension WindowCoordinator {
    
    /// Presents a managed window for the given ID, creating it if it doesn't exist or bringing it
    /// to the front if it's already open.
    ///
    /// Subsequent calls with the same `id` will skip creation and simply re-focus the existing
    /// window — none of the other parameters will have any effect on that call.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for the window. Used to track and deduplicate instances.
    ///   - title: The window's title. Hidden from the titlebar but used by the system (e.g. Mission Control).
    ///   - content: The SwiftUI view to embed as the window's content.
    ///   - size: The initial size of the window. Defaults to 600×400. Ignored if the window already exists.
    ///   - origin: The window's initial screen position. If `nil`, the window is centered on screen.
    ///   - makeGlass: If `true`, applies a vibrancy/glass effect and clears the background. Defaults to `false`.
    ///   - onOpen: Called when the window first becomes key.
    ///   - onClose: Called when the window is closed.
    ///   - onBlur: Called when the window loses focus.
    ///   - onResize: Called when a resize event occurs. The `Bool` parameter indicates whether
    ///     the window's frame actually changed.
    ///
    /// - Returns: The managed `NSWindow` instance, whether newly created or already existing.
    @discardableResult
    func showWindow(
        id: String,
        title: String,
        content: some View,
        size: NSSize = .init(width: 600, height: 400),
        origin: CGPoint? = nil,
        makeGlass: Bool = false,
        onOpen: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onBlur: (() -> Void)? = nil,
        onResize: ((Bool) -> Void)? = nil
    ) -> NSWindow {
        if let window = windows[id] {
            // Re-activate app and bring the existing window up
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
            return window
        }
        
        let windowOrigin = origin ?? .zero
        
        let window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // Match SwiftUI window modifiers
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        
        let hostingView = NSHostingView(rootView: content)
        hostingView.wantsLayer = true
        if makeGlass {
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            hostingView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        window.contentView = hostingView
        
        /// Assign A Window Delegate
        let delegate = WindowDelegate(id: id, coordinator: self)
        window.delegate = delegate
        delegates[id] = delegate
        
        if let action = onClose {
            onCloseAction[id] = action
        }
        if let action = onOpen {
            onOpenAction[id] = action
        }
        if let action = onBlur {
            onBlurAction[id] = action
        }
        if let action = onResize {
            onResizeAction[id] = action
        }
        
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        windows[id] = window
        
        if makeGlass {
            makeWindowGlass(window)
        }
        
        return window
    }
    
    func makeWindowGlass(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        
        // Get the existing hosting view
        guard let hostingView = window.contentView else { return }
        
        // Make a container view to hold both
        let containerView = NSView(frame: hostingView.frame)
        containerView.autoresizingMask = [.width, .height]
        
        // Glass goes in the container as the base
        let glassView = NSGlassEffectView()
        glassView.style = .regular
        glassView.frame = containerView.bounds
        glassView.autoresizingMask = [.width, .height]
        containerView.addSubview(glassView)
        
        // Hosting view goes on top inside the container
        hostingView.removeFromSuperview()
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingView)
        
        // Container becomes the window's content view
        window.contentView = containerView
    }
}

extension WindowCoordinator {
    func closeWindow(id: String) {
        windows[id]?.close()
        /// windowWillClose will be called automatically
    }
    
    fileprivate func handleWindowResize(id: String, isResizing: Bool) {
        onResizeAction[id]?(isResizing)
    }
    
    fileprivate func handleWindowBlur(id: String) {
        if let action = onBlurAction[id] {
            action()
            onBlurAction[id] = nil
        }
    }
    
    fileprivate func handleWindowOpen(id: String) {
        if let action = onOpenAction[id] {
            action()
            onOpenAction[id] = nil
        }
    }
    
    fileprivate func handleWindowClose(id: String) {
        windows[id] = nil
        delegates[id] = nil
        onOpenAction[id] = nil
        onBlurAction[id] = nil
        onResizeAction[id] = nil
        
        if let action = onCloseAction[id] {
            action()
            onCloseAction[id] = nil
        }
    }
}

// MARK: - Rename
extension WindowCoordinator {
    /// Renames an existing window's identifier and (optionally) its title.
    /// - Parameters:
    ///   - oldId: Current id used in the coordinator maps.
    ///   - newId: New id you want to use.
    ///   - newTitle: Optional new title to display in the titlebar.
    /// - Returns: true if the rename happened, false otherwise.
    @discardableResult
    public func changeWindowName(from oldId: String, to newId: String, newTitle: String? = nil) -> Bool {
        precondition(Thread.isMainThread, "Must be called on main thread")
        
        // window must exist
        guard let window = windows[oldId] else { return false }
        // don't clobber an existing entry
        guard windows[newId] == nil else { return false }
        
        // move window map
        windows.removeValue(forKey: oldId)
        windows[newId] = window
        
        // move actions if present
        if let open = onOpenAction.removeValue(forKey: oldId) {
            onOpenAction[newId] = open
        }
        if let close = onCloseAction.removeValue(forKey: oldId) {
            onCloseAction[newId] = close
        }
        if let blur = onBlurAction.removeValue(forKey: oldId) {
            onBlurAction[newId] = blur
        }
        if let resize = onResizeAction.removeValue(forKey: oldId) {
            onResizeAction[newId] = resize
        }
        
        // refresh delegate with the new id (simplest is to swap in a new one)
        let newDelegate = WindowDelegate(id: newId, coordinator: self)
        window.delegate = newDelegate
        delegates[oldId] = nil
        delegates[newId] = newDelegate
        
        // update title if requested
        if let t = newTitle {
            window.title = t
        }
        
        return true
    }
    
    /// Just change the visible title without touching ids.
    public func setTitle(for id: String, to title: String) {
        precondition(Thread.isMainThread, "Must be called on main thread")
        windows[id]?.title = title
    }
    
    public func activateWithRetry(_ tries: Int = 6) {
        guard tries > 0 else { return }
        
        // If we're already active *and* have a key window, stop retrying.
        if NSApp.isActive, NSApp.keyWindow != nil {
            return
        }
        
        bringAppFront()
        
        // Try again shortly — gives Spaces/full-screen a moment to switch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.activateWithRetry(tries - 1)
        }
    }
    
    public func bringAppFront() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }
}
