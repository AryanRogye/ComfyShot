# Create Readable Code Using Extensions

Use extensions to divide a large Swift type into sections that are easy for
humans to scan. Section names should make it obvious what code belongs there.
Category-style names are encouraged when they communicate the structure
clearly, even when they are nouns rather than verb phrases.

The `MenuBarCoordinator` example below shows the preferred style. The section
names describe the human-facing organization of the type:

```swift
// MARK: - Menubar Actions
extension MenuBarCoordinator { ... }

// MARK: - Delegate Functions
extension MenuBarCoordinator { ... }

// MARK: - Build Menu Items
extension MenuBarCoordinator { ... }

// MARK: - Shortcut Observation
extension MenuBarCoordinator { ... }

// MARK: - Update Observation
extension MenuBarCoordinator { ... }
```

Keep the main declaration focused on stored state, initialization, and the
primary public entry points. Put related implementation behind clearly named
extensions and order those sections according to how a reader encounters the
type. Use a `MARK` before each extension so the file remains easy to navigate.

```swift
//
//  WindowCore.swift
//  ComfyTile
//
//  Created by Aryan Rogye on 1/15/26.
//

import Foundation
import ScreenCaptureKit

@Observable
@MainActor
public final class WindowCore {
    
    /**
     * All User Windows
     */
    public var windows: [ComfyWindow] = []
    
    /**
     We cache WindowElements when the window is in the active Space
     because they behave more reliably.
     
     AXUIElements can act differently depending on when/how they’re grabbed.
     Reusing a previously cached one keeps window interactions stable.
     */
    private var elementCache: [CGWindowID: WindowElement] = [:]
    
    var bootTask : Task<Void, Never>?
    
    /**
     * This is the task that holds a run of the loadTask in a non async function
     */
    private var unAsyncLoadWindowTask: Task<Void, Never>?
    
    /**
     * Main Load Window Task
     */
    var loadWindowTask: Task<[ComfyWindow], Never>?

    @ObservationIgnored
    static let ignore_list = [
        "com.aryanrogye.ComfyTile"
    ]
    
    /**
     * These are all related to highlighting focused windows or
     * super focusing, windowSubscriptions is only populated if
     * either are true
     */
    var highlightFocusedWindow: Bool = false
    var superFocusWindow: Bool = false
    
    /**
     * Contains a mapping of pid -> subscription
     */
    @ObservationIgnored
    public var windowSubscriptions: [pid_t: AXSubscription] = [:]
    
    /**
     * What happens when a AXElement is changed
     * this is set by other classes, but this will run only if either
     * highlightFocusedWindow || superFocusWindow
     */
    var onNewFrame: ((ComfyWindow?, [HighlightConfiguration], Bool) -> Void)?
    
    
    /**
     * Observers are used for knowing when a app got focused
     * and for when spaces got changed, this lets us call our
     * getFocusedWindow function and set that window to the
     * 0th index or the most recent cuz it is
     */
    private var observers: [NSObjectProtocol] = []
    
    public init() {
        bootTask = Task { [weak self] in
            guard let self else { return }
            /// Initial Load of all windows
            await self.loadWindows()
            /// Begin Observation tracking on highlightFocusedWindow and superFocusWindow
            observeFocusedWindow()
            /// Assign Possible Observations we wanna watch for
            assignObservers()
        }
    }
    
    @MainActor
    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
    }
}

// MARK: - Initial Boot
extension WindowCore {
    
    /**
     * Observes focus-related toggles (`highlightFocusedWindow`, `superFocusWindow`)
     * and dynamically manages AX subscriptions based on their state.
     *
     * When both are disabled, all subscriptions are cleared to avoid unnecessary work.
     * When at least one is enabled, subscriptions are attached to track focus changes.
     *
     * Re-triggers itself on change to keep the observation cycle alive.
     */
    internal func observeFocusedWindow() {
        withObservationTracking {
            _ = highlightFocusedWindow;
            _ = superFocusWindow
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                
                let isHighlightFocusWindow = self.highlightFocusedWindow
                let isSuperFocusWindow = self.superFocusWindow
                
                if !isHighlightFocusWindow && !isSuperFocusWindow {
                    self.clearSubscriptions()
                }
                /// Else falls through if at least 1 is true
                else {
                    self.attachSubscriptionsOnAllWindows()
                }
                
                self.emitCurrentFocusedState()
                
                self.observeFocusedWindow()
            }
        }
    }
    
    /**
     * Subscribes to workspace-level events (**App Activation**, **Space Change**)
     * to keep the internal window ordering in sync with system focus.
     *
     * Whenever the active app or space changes, the currently focused window
     * is moved to the front of our tracked windows list.
     */
    internal func assignObservers() {
        let center = NSWorkspace.shared.notificationCenter
        
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.addFocusedToFront()
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.addFocusedToFront()
                }
            }
        )
    }

    /**
     * Function Forces a onNewFrame call
     * this can be used to give info to whoever is setting
     * this quickly for turning/hiding states
     */
    private func emitCurrentFocusedState() {
        let config = currentHighlightConfig()
        guard !config.isEmpty else {
            onNewFrame?(nil, [], false)
            return
        }
        let win = getFocusedWindow()
        onNewFrame?(win, config, isFullScreen(on: win))
    }
}

// MARK: - AXSubscriptions
extension WindowCore {
    private func assignHandler(subscription: AXSubscription) {
        subscription.setHandlerIfNeeded { [weak self] pid, _, notif in
            guard let self else { return }
            
            guard let win = self.activeWindowElement(for: pid) else { return }
            var comfyWindow = getFocusedWindow()
            
            /// if the focusedWindow != what the notification was
            if let id = win.cgWindowID, id != comfyWindow?.windowID {
                    /// We Can use windows api to get something stronger
                    /// Window state may already be cached/synchronized elsewhere.
                    /// lol funny ass bug, if we have { $0.windowID == win.cgWindowID } and its both nil, itll fall through
                if let win = windows.first(where: { $0.windowID == id }) {
                    comfyWindow = win
                }
            }
            
            guard let comfyWindow else {
                print("Couldnt Find Valid ComfyWindow"); return
            }
            
            onNewFrame?(comfyWindow, currentHighlightConfig(), isFullScreen(on: comfyWindow))
            
//            print("\(comfyWindow.windowTitle) [\(comfyWindow.app.localizedName, default: "[NIL]")]")
//            if notif as String == kAXFocusedUIElementChangedNotification as String {
//                print("Element Changed | id:", win.cgWindowID ?? "Unkown ID")
//            }
//            if notif as String == kAXFocusedWindowChangedNotification as String {
//                print("Focused window Changed | id:", win.cgWindowID ?? "Unkown ID")
//            }
//            if notif as String == kAXApplicationActivatedNotification as String {
//                print("Application Activated | id:", win.cgWindowID ?? "Unkown ID")
//            }
//            if notif as String == kAXWindowMovedNotification as String {
//                print("Window Moved | id:", win.cgWindowID ?? "Unkown ID")
//            }
//            if notif as String == kAXWindowResizedNotification as String {
//                print("Window Resized | id:", win.cgWindowID ?? "Unkown ID")
//            }
//            if notif as String == kAXMovedNotification as String {
//                print("Window Moved | id:", win.cgWindowID ?? "Unkown ID")
//            }
//            if notif as String == kAXResizedNotification as String {
//                print("Window Resized | id:", win.cgWindowID ?? "Unkown ID")
//            }
//            print("====================END==================")
        }
    }
    
    private func attachAppWatcher(subscription: AXSubscription?, pid: pid_t) {
        guard let sub = subscription else { return }
        
        // set onChange ONCE per subscription
        sub.watchApp()
    }
    
    private func attachWindowWatcher(subscription: AXSubscription?, windowEl: AXUIElement?, windowID: CGWindowID?) {
        guard let sub = subscription, let windowEl, let windowID else { return }
        sub.watchWindow(windowEl, windowID: windowID)
    }
    
    /// Main API For
    internal func attachSubscriptionIfNeeded(pid: pid_t, windowEl: AXUIElement?, windowID: CGWindowID?) {
        guard highlightFocusedWindow || superFocusWindow else { return }
        /// if we come in as a "false" on usedAppElement we can test to see if a true one exists
        if self.windowSubscriptions[pid] == nil {
            /// if we dont have a subscription stored
            /// if we can make a valid subscription
            if let sub = AXSubscription(pid: pid) {
                /// add it in
                self.windowSubscriptions[pid] = sub
            }
        }
        
        if let sub = self.windowSubscriptions[pid] {
            self.attachAppWatcher(subscription: sub, pid: pid)
            self.attachWindowWatcher(subscription: sub, windowEl: windowEl, windowID: windowID)
            self.assignHandler(subscription: sub)
        }
    }
    
    internal func clearSubscriptions() {
        self.windowSubscriptions.removeAll()
    }
    
    internal func attachSubscriptionsOnAllWindows() {
        for cw in windows {
            if self.windowSubscriptions[cw.pid] == nil {
                self.attachSubscriptionIfNeeded(
                    pid: cw.pid,
                    windowEl: cw.element.element,
                    windowID: cw.windowID
                )
            }
        }
    }
}

// MARK: - Main Loading Of Windows
extension WindowCore {
    public func unAsyncLoadWindows(completion: @escaping () -> Void) {
        unAsyncLoadWindowTask?.cancel()
        unAsyncLoadWindowTask = Task {
            await loadWindows()
            completion()
        }
    }

    @discardableResult
    public func loadWindows() async -> [ComfyWindow] {
        loadWindowTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return [] }
            var userWindows: [ComfyWindow] = []

            let cscWindows: [ComfySCWindow] = await SCWindowFactory.getComfyWindowsPrivately(onScreenWindowsOnly: false)

            for w in cscWindows {
                /// Create a ComfyWindow Object
                if let cw = await ComfyWindow(window: w) {
                    
                    await MainActor.run {
                        if let windowID = cw.windowID {
                            /// if the element in ComfyWindow is a valid AXUIElement?, we can update cache
                            if cw.element.element != nil {
                                self.elementCache[windowID] = cw.element
                            }
                            /// if AXUIElement is nil, we can check our cache and update
                            else if let element = self.elementCache[windowID] {
                                cw.element = element
                            }
                            /// Brute-force fallback: resolve via _AXUIElementCreateWithRemoteToken
                            /// This catches windows on other Spaces, minimized, or hidden
                            /// that neither standard AX nor our cache can find
                            else if let ax = WindowServerBridge.shared.resolveAXElement(
                                pid: cw.pid,
                                windowID: windowID
                            ) {
                                let resolved = WindowElement(element: ax)
                                cw.element = resolved
                                self.elementCache[windowID] = resolved
                            }
                        }
                        
                        self.attachSubscriptionIfNeeded(
                            pid: cw.pid,
                            windowEl: cw.element.element,
                            windowID: cw.windowID
                        )
                    }
                    /// Add Window into userWindows
                    userWindows.append(cw)
                    
                }
            }
            /// Return of the task
            return userWindows
        }
        
        
        if let loadWindowTask = loadWindowTask {
            let userWindows = await loadWindowTask.value
            if userWindows.isEmpty { return [] }
            
            // fast lookup of the newest snapshot by windowID
            let newByID = Dictionary(uniqueKeysWithValues: userWindows.map { ($0.windowID, $0) })
            
            var merged: [ComfyWindow] = []
            merged.reserveCapacity(userWindows.count)
            
            // 1) preserve previous order (self.windows), refreshing data when present
            var seen = Set<String>()
            seen.reserveCapacity(userWindows.count)
            
            for old in self.windows {
                if let updated = newByID[old.windowID] {
                    merged.append(updated)
                    seen.insert(old.id)
                }
            }
            
            // 2) append any brand-new windows (order = snapshot order for new ones)
            for w in userWindows where !seen.contains(w.id) {
                merged.append(w)
                seen.insert(w.id)
            }
            
            self.windows = merged
            return merged
        } else {
            return []
        }
    }
    
    public func quit(_ window: ComfyWindow) {
        /// find the index
        guard let index = windows.firstIndex(where: {$0.id == window.id }) else { return }
        windows.remove(at: index)
        window.element.quit()
    }
    /**
     * Public function to focus the window at the specified index
     * this then ads the window to the front of the list
     */
    public func focusWindow(at index: Int) {
        if windows.indices.contains(index) {
            windows[index].focusWindow()
            addWindowToFront(at: index)
        }
    }
}

// MARK: - Main Focus Window
extension WindowCore {
    
    internal func activeWindowElement(for pid: pid_t) -> WindowElement? {
        let appEl = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        let r = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &focused)
        guard r == .success, let focused else { return nil }
        // Ensure the returned CFType is actually an AXUIElement before casting
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        
        return WindowElement(element: element)
    }

    
    /// This is used for Tiling + Layouts
    ///
    /// Layouts, use focusing on the WindowElement then call Focus

    public func getFocusedWindow() -> ComfyWindow? {
        // If we can't get the screen under the mouse, stop.
        guard let screen = Self.screenUnderMouse() else {
            print("❌ Failed to determine screen under mouse")
            return nil
        }
        
        // Get the frontmost app.
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard let bundle = app.bundleIdentifier else { return nil }
        let pid = app.processIdentifier
        
        if Self.ignore_list.contains(bundle) { return nil }
        
        let appElement = AXUIElementCreateApplication(pid)
        
        // Ask Accessibility for the app's focused window.
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        // If that fails, stop.
        if result != .success {
            print("❌ Failed to get focused window: \(result)")
            return nil
        }
        let windowElement = focusedWindow as! AXUIElement
        let element : WindowElement = WindowElement(element: windowElement)

        self.attachSubscriptionIfNeeded(
            pid: app.processIdentifier,
            windowEl: element.element,
            windowID: element.cgWindowID
        )
        
        return ComfyWindow(
            app: app,
            windowID: element.cgWindowID,
            windowTitle: element.title ?? "Unamed",
            element: element,
            screen: screen,
            bundleIdentifier: app.bundleIdentifier,
            pid: app.processIdentifier,
            /// Most Likely Focused will always be in space
            isInSpace: true
        )
    }
}

// MARK: - Helpers
extension WindowCore {
    
    /**
     * Function Adds the Focused Window to the
     * front of the windows list by making
     * sure we have a valid windowID, we find it
     * in our windows list and we bump
     * it to the 0th or first index
     */
    internal func addFocusedToFront() {
        if let w = getFocusedWindow(),
           let wID = w.windowID,
           let index = windows.firstIndex(where: { $0.windowID == wID }) {
            addWindowToFront(at: index)
        }
    }
    
    /**
     * Function moves the window at the specified index
     * to the front of the windows list by making it the
     * 0th index
     */
    internal func addWindowToFront(at index: Int) {
        if windows.indices.contains(index) {
            /// Remove
            let focused = windows.remove(at: index)
            
            /// Add to front
            windows.insert(focused, at: 0)
        }
    }
    
    /**
     * TODO: Remember what this does its been a min
     */
    internal func currentHighlightConfig() -> [HighlightConfiguration] {
        var config: [HighlightConfiguration] = []
        if highlightFocusedWindow {
            config.append(.border)
        }
        if superFocusWindow {
            config.append(.superFocus)
        }
        return config
    }
    
    /**
     * Function Returns true if the window
     * is fullscreen or not
     */
    internal func isFullScreen(
        on window: ComfyWindow?
    ) -> Bool {
        if let element = window?.element.element {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element,
                                          kAXFullscreenAttribute as CFString,
                                          &value)
            if let bool = value as? Bool {
                return bool
            }
        }
        return false
    }

    /// Global Helper
    
    /**
     * Grab the screen under the mouse
     */
    public static func screenUnderMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first {
            NSMouseInRect(loc, $0.frame, false)
        }
    }
}
```
