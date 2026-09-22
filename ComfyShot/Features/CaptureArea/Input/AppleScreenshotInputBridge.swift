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
/// moving it, resizing it, and setting the system cursor shape.
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
    private let cursorController = SystemCursorController()
    private var overlayContexts: [OverlayContext] = []

    /// A drag stays attached to the display where it began.
    private var activeInputContext: OverlayContext?
    private var dragOperation: DragOperation?

    /// These sizes mirror `SelectionRect` so both input paths resize identically.
    private let edgeHitWidth: CGFloat = 8
    private let cornerHitSize: CGFloat = 18

    /// Starts isolated input and returns whether the event tap became active.
    ///
    /// When this succeeds, the tap consumes input before the foreground app or
    /// Dock receives it, preserving their last menu and hover state.
    @discardableResult
    func start(contexts: [OverlayContext], onCancel: @escaping () -> Void) -> Bool {
        overlayContexts = contexts

        let didStart = inputInterceptor.start(
            mouseDown: { [weak self] in self?.handleMouseDown(at: $0) },
            mouseDragged: { [weak self] in self?.handleMouseDragged(to: $0) },
            mouseUp: { [weak self] in self?.handleMouseUp(at: $0) },
            mouseMoved: { [weak self] in self?.updateCursor(at: $0) },
            cancel: onCancel,
            capture: { [weak self] in self?.captureSelectedRect() }
        )

        if didStart {
            updateCursor(at: NSEvent.mouseLocation)
        } else {
            print("Capture input interceptor could not start. Accessibility/Input Monitoring permission may be required.")
        }
        return didStart
    }

    /// Ends input interception and clears every piece of session-only state.
    func stop() {
        inputInterceptor.stop()
        cursorController.stop()
        overlayContexts = []
        activeInputContext = nil
        dragOperation = nil
    }

    /// Restores the capture cursor after the panels install their cursor rects.
    func refreshCursor() {
        updateCursor(at: NSEvent.mouseLocation)
    }
}

// MARK: - Drag Input
extension AppleScreenshotInputBridge {
    /// Chooses whether this drag draws, moves, or resizes a selection.
    private func handleMouseDown(at globalPoint: CGPoint) {
        updateCursor(at: globalPoint)

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
            cursorController.setCursor(CaptureCursorOverride.resizeCursor(for: edge))
        } else if selectionRect.contains(localPoint) {
            dragOperation = .moving(startPoint: localPoint)
            cursorController.setCursor(.closedHand)
        } else {
            beginDrawing(at: localPoint, in: context)
        }
    }

    /// Applies cumulative translation from the original mouse-down point.
    private func handleMouseDragged(to globalPoint: CGPoint) {
        updateCursor(at: globalPoint)
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
        updateCursor(at: globalPoint)
        defer {
            activeInputContext = nil
            dragOperation = nil
            updateCursor(at: globalPoint)
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

// MARK: - System Cursor
extension AppleScreenshotInputBridge {
    private func updateCursor(at globalPoint: CGPoint) {
        if let dragOperation {
            switch dragOperation {
            case .drawing:
                cursorController.setCursor(.crosshair)
            case .moving:
                cursorController.setCursor(.closedHand)
            case .resizing(let edge, _):
                cursorController.setCursor(CaptureCursorOverride.resizeCursor(for: edge))
            }
            return
        }

        guard let context = overlayContext(containing: globalPoint),
              let localPoint = localOverlayPoint(for: globalPoint, in: context.panel) else {
            cursorController.setCursor(.crosshair)
            return
        }

        cursorController.setCursor(cursor(at: localPoint, in: context))
    }

    /// Chooses the cursor from the selection hit region under the pointer.
    /// This mirrors `SelectionRect`'s fallback.
    private func cursor(at point: CGPoint, in context: OverlayContext) -> NSCursor {
        guard let selectionRect = context.model.selectionRect else {
            return .crosshair
        }
        if let edge = resizeEdge(at: point, in: selectionRect) {
            return CaptureCursorOverride.resizeCursor(for: edge)
        }
        if selectionRect.contains(point) {
            return .openHand
        }
        return .crosshair
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
