//
//  DisplayImageStack.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import AppKit
import SwiftUI

/// Owns the floating screenshot stack for a single physical display.
///
/// There is at most one `DisplayImageStack` per monitor.
/// The stack is responsible for:
/// - Storing the screenshots displayed on that monitor.
/// - Creating and owning the floating `NSPanel`.
/// - Updating the SwiftUI view whenever the image list changes.
/// - Destroying the panel once the last screenshot is removed.
///
/// The `UserImageCoordinator` creates and manages these stacks.
@MainActor
final class DisplayImageStack {

    /// Observable state consumed by the SwiftUI image list.
    let model = DisplayImageStackModel()
    
    /// Floating panel shown on the display.
    /// Created lazily the first time an image is added.
    private var panel: FocusablePanel?
    
    /// Hosts the SwiftUI content inside the floating panel.
    /// Kept alive so the root view can be updated without recreating the panel.
    private var hostingView: NSHostingView<UserImageListView>?

    func addImage(_ userImage: UserImage) {
        model.images.append(userImage)
    }
    
    public func hide() {
        panel?.orderOut(nil)
    }
    
    public func show() {
        guard !model.images.isEmpty else { return }
        panel?.orderFrontRegardless()
    }

    /// Presents or updates the floating image stack on a display.
    ///
    /// If the panel already exists, its SwiftUI content is refreshed.
    /// Otherwise a new floating panel is created and attached to the screen.
    func present(
        on screen: NSScreen,
        padding: ImageStackPadding,
        imageSpacing: CGFloat
    ) {
        let placement = placementForStack(on: screen, padding: padding)
        let view = UserImageListView(
            model: model,
            spacing: imageSpacing,
            placement: placement,
            onClose: { [weak self] image in
                guard let self else { return }
                model.remove(image)

                if self.model.images.isEmpty {
                    self.closePanel()
                }
            }
        )

        if let panel, let hostingView {
            // Reuse the existing panel instead of recreating one every time a
            // screenshot is added. Only the SwiftUI root view needs updating.
            hostingView.rootView = view
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            return
        }

        let panel = FocusablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(screen.frame, display: true)

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false

        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = false
        panel.contentView = hostingView
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hostingView
    }

    /// Destroys the floating panel and releases all AppKit resources.
    ///
    /// The image model itself is intentionally left untouched. The owner
    /// decides whether the stack should continue existing.
    func closePanel() {
        panel?.close()
        panel = nil
        hostingView = nil
    }

    /// Computes where the image stack should appear within the display.
    ///
    /// Uses the visible frame instead of the full screen so screenshots
    /// never appear underneath the menu bar or Dock.
    private func placementForStack(
        on screen: NSScreen,
        padding: ImageStackPadding
    ) -> ImageStackPlacement {
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        return ImageStackPlacement(
            leadingInset: visibleFrame.minX - screenFrame.minX + padding.leadingPadding,
            bottomInset: visibleFrame.minY - screenFrame.minY + padding.bottomPadding,
            maxHeight: max(1, visibleFrame.height - padding.topPadding * 2)
        )
    }
}
