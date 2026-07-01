//
//  AppleScreenshotInputBridge.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import AppKit
import CoreGraphics

@MainActor
final class AppleScreenshotInputBridge {
    private let inputInterceptor = CaptureInputInterceptor()
    private var overlayContexts: [OverlayContext] = []
    private var activeInputContext: OverlayContext?

    func startIfNeeded(
        contexts: [OverlayContext],
        onCancel: @escaping () -> Void
    ) {
        guard isAppleScreenshotUIActive() else {
            stop()
            return
        }

        overlayContexts = contexts

        let didStart = inputInterceptor.start(
            handlers: CaptureInputInterceptor.Handlers(
                mouseDown: { [weak self] point in
                    self?.handleGlobalMouseDown(at: point)
                },
                mouseDragged: { [weak self] point in
                    self?.handleGlobalMouseDragged(to: point)
                },
                mouseUp: { [weak self] point in
                    self?.handleGlobalMouseUp(at: point)
                },
                cancel: onCancel,
                capture: { [weak self] in
                    self?.captureSelectedRect()
                }
            )
        )

        if !didStart {
            print("Capture input interceptor could not start. Accessibility/Input Monitoring permission may be required.")
        }
    }

    func stop() {
        inputInterceptor.stop()
        activeInputContext = nil
        overlayContexts = []
    }

    private func isAppleScreenshotUIActive() -> Bool {
        guard let windowInfos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        return windowInfos.contains { info in
            let owner = info[kCGWindowOwnerName as String] as? String
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0

            return owner == "screencapture" && layer >= 1000
        }
    }

    private func handleGlobalMouseDown(at point: CGPoint) {
        guard let context = overlayContext(containing: point),
              let localPoint = localOverlayPoint(for: point, in: context.panel)
        else {
            activeInputContext = nil
            return
        }

        activeInputContext = context
        context.model.beginDrag(at: localPoint)
    }

    private func handleGlobalMouseDragged(to point: CGPoint) {
        guard let context = activeInputContext,
              let localPoint = localOverlayPoint(for: point, in: context.panel)
        else { return }

        context.model.updateDrag(to: localPoint)
    }

    private func handleGlobalMouseUp(at point: CGPoint) {
        guard let context = activeInputContext,
              let localPoint = localOverlayPoint(for: point, in: context.panel)
        else {
            activeInputContext = nil
            return
        }

        context.model.endDrag(at: localPoint)
        activeInputContext = nil
    }

    private func captureSelectedRect() {
        overlayContexts
            .first { $0.model.selectionRect != nil }
            .map { $0.model.captureSelection() }
    }

    private func overlayContext(containing point: CGPoint) -> OverlayContext? {
        overlayContexts.first {
            NSMouseInRect(point, $0.panel.frame, false)
        }
    }

    private func localOverlayPoint(for point: CGPoint, in panel: NSPanel) -> CGPoint? {
        guard panel.frame.contains(point) else { return nil }

        return CGPoint(
            x: point.x - panel.frame.minX,
            y: panel.frame.maxY - point.y
        )
    }
}
