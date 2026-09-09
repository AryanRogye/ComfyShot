//
//  AppleScreenshotInputBridge.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import AppKit
import CoreGraphics

/// Turns intercepted global input into capture-area model updates.
///
/// `CaptureInputInterceptor` owns the macOS event system. This bridge owns the
/// capture meaning of those events: choosing a display, drawing a selection,
/// moving it, resizing it, and positioning ComfyShot's virtual cursor.
///
/// The name is historical. The bridge originally existed only for capturing
/// over Apple's screenshot UI, but it now drives every isolated area capture.
@MainActor
final class AppleScreenshotInputBridge {
    /// Mouse-down chooses one operation for the complete drag. The start point is
    /// retained because `CaptureAreaModel` expects translation from drag start.
    private enum DragOperation {
        case drawing
        case moving(startPoint: CGPoint)
        case resizing(edge: CaptureResizeEdge, startPoint: CGPoint)
    }

    private let inputInterceptor = CaptureInputInterceptor()
    private var overlayContexts: [OverlayContext] = []

    /// A drag stays attached to the display where it began, even when the virtual
    /// pointer reaches that display's edge.
    private var activeInputContext: OverlayContext?
    private var dragOperation: DragOperation?

    /// These sizes mirror `SelectionRect` so both input paths resize identically.
    private let edgeHitWidth: CGFloat = 8
    private let cornerHitSize: CGFloat = 18

    /// Starts isolated input and returns whether the event tap became active.
    ///
    /// When this succeeds, overlay panels can ignore AppKit mouse events and stay
    /// non-key. That is what preserves open menus and Dock hover state.
    @discardableResult
    func start(contexts: [OverlayContext], onCancel: @escaping () -> Void) -> Bool {
        overlayContexts = contexts

        let didStart = inputInterceptor.start(
            mouseDown: { [weak self] in self?.handleMouseDown(at: $0) },
            mouseDragged: { [weak self] in self?.handleMouseDragged(to: $0) },
            mouseUp: { [weak self] in self?.handleMouseUp(at: $0) },
            mouseMoved: { [weak self] in self?.updateVirtualCursor(to: $0) },
            cancel: onCancel,
            capture: { [weak self] in self?.captureSelectedRect() }
        )

        if didStart {
            updateVirtualCursor(to: NSEvent.mouseLocation)
        } else {
            print("Capture input interceptor could not start. Accessibility/Input Monitoring permission may be required.")
        }
        return didStart
    }

    /// Ends input interception and clears every piece of session-only state.
    func stop() {
        inputInterceptor.stop()
        overlayContexts.forEach { $0.model.virtualCursorLocation = nil }
        overlayContexts = []
        activeInputContext = nil
        dragOperation = nil
    }

    /// Hides the hardware cursor after the coordinator presents its panels.
    /// Waiting prevents panel cursor rectangles from undoing the hide.
    func hideSystemCursor() {
        inputInterceptor.hideSystemCursor()
    }
}

// MARK: - Drag Input
extension AppleScreenshotInputBridge {
    /// Chooses whether this drag draws, moves, or resizes a selection.
    private func handleMouseDown(at globalPoint: CGPoint) {
        updateVirtualCursor(to: globalPoint)

        guard let context = overlayContext(containing: globalPoint),
              let localPoint = localOverlayPoint(for: globalPoint, in: context.panel) else {
            activeInputContext = nil
            dragOperation = nil
            return
        }

        activeInputContext = context
        guard let selectionRect = context.model.selectionRect else {
            beginDrawing(at: localPoint, in: context)
            return
        }

        if let edge = resizeEdge(at: localPoint, in: selectionRect) {
            dragOperation = .resizing(edge: edge, startPoint: localPoint)
        } else if selectionRect.contains(localPoint) {
            dragOperation = .moving(startPoint: localPoint)
        } else {
            beginDrawing(at: localPoint, in: context)
        }
    }

    /// Applies cumulative translation from the original mouse-down point.
    private func handleMouseDragged(to globalPoint: CGPoint) {
        updateVirtualCursor(to: globalPoint)
        guard let context = activeInputContext,
              let localPoint = localOverlayPoint(for: globalPoint, in: context.panel) else { return }

        switch dragOperation {
        case .drawing:
            context.model.updateDrag(to: localPoint)
        case .moving(let startPoint):
            context.model.moveSelection(translation: translation(from: startPoint, to: localPoint))
        case .resizing(let edge, let startPoint):
            context.model.resizeSelection(
                edge: edge,
                translation: translation(from: startPoint, to: localPoint)
            )
        case nil:
            break
        }
    }

    /// Commits the active model operation, then releases drag ownership.
    private func handleMouseUp(at globalPoint: CGPoint) {
        updateVirtualCursor(to: globalPoint)
        defer {
            activeInputContext = nil
            dragOperation = nil
        }

        guard let context = activeInputContext,
              let localPoint = localOverlayPoint(for: globalPoint, in: context.panel) else { return }

        switch dragOperation {
        case .drawing:
            context.model.endDrag(at: localPoint)
        case .moving:
            context.model.endMove()
        case .resizing:
            context.model.endResize()
        case nil:
            break
        }
    }

    /// Starts a fresh selection and records that subsequent movement is drawing.
    private func beginDrawing(at point: CGPoint, in context: OverlayContext) {
        dragOperation = .drawing
        context.model.beginDrag(at: point)
    }

    /// Produces the drag-start translation expected by `CaptureAreaModel`.
    private func translation(from startPoint: CGPoint, to currentPoint: CGPoint) -> CGSize {
        CGSize(
            width: currentPoint.x - startPoint.x,
            height: currentPoint.y - startPoint.y
        )
    }
}

// MARK: - Virtual Cursor
extension AppleScreenshotInputBridge {
    /// Draws the replacement cursor only on the display containing this point.
    private func updateVirtualCursor(to globalPoint: CGPoint) {
        for context in overlayContexts {
            context.model.virtualCursorLocation = localOverlayPoint(
                for: globalPoint,
                in: context.panel
            )
        }
    }
}

// MARK: - Selection Hit Testing
extension AppleScreenshotInputBridge {
    /// Recreates `SelectionRect` resize regions. Corners take priority because
    /// their hit regions overlap the straight edges.
    private func resizeEdge(at point: CGPoint, in rect: CGRect) -> CaptureResizeEdge? {
        let nearLeft = abs(point.x - rect.minX) <= edgeHitWidth
        let nearRight = abs(point.x - rect.maxX) <= edgeHitWidth
        let nearTop = abs(point.y - rect.minY) <= edgeHitWidth
        let nearBottom = abs(point.y - rect.maxY) <= edgeHitWidth
        let isNearSelectionX = point.x >= rect.minX - cornerHitSize
            && point.x <= rect.maxX + cornerHitSize
        let isNearSelectionY = point.y >= rect.minY - cornerHitSize
            && point.y <= rect.maxY + cornerHitSize

        guard isNearSelectionX, isNearSelectionY else { return nil }
        if nearTop && nearLeft { return .topLeading }
        if nearTop && nearRight { return .topTrailing }
        if nearBottom && nearLeft { return .bottomLeading }
        if nearBottom && nearRight { return .bottomTrailing }
        if nearTop && rect.minX...rect.maxX ~= point.x { return .top }
        if nearBottom && rect.minX...rect.maxX ~= point.x { return .bottom }
        if nearLeft && rect.minY...rect.maxY ~= point.y { return .leading }
        if nearRight && rect.minY...rect.maxY ~= point.y { return .trailing }
        return nil
    }
}

// MARK: - Capture Command
extension AppleScreenshotInputBridge {
    /// Enter captures the first display that currently owns a selection.
    private func captureSelectedRect() {
        guard let context = overlayContexts.first(where: { $0.model.selectionRect != nil }) else {
            return
        }
        context.model.captureSelection()
    }
}

// MARK: - Coordinate Conversion
extension AppleScreenshotInputBridge {
    /// Finds the overlay beneath an AppKit global screen point.
    private func overlayContext(containing globalPoint: CGPoint) -> OverlayContext? {
        overlayContexts.first {
            NSMouseInRect(globalPoint, $0.panel.frame, false)
        }
    }

    /// Converts bottom-left global coordinates into top-left SwiftUI coordinates.
    private func localOverlayPoint(for globalPoint: CGPoint, in panel: NSPanel) -> CGPoint? {
        guard panel.frame.contains(globalPoint) else { return nil }
        return CGPoint(
            x: globalPoint.x - panel.frame.minX,
            y: panel.frame.maxY - globalPoint.y
        )
    }
}
