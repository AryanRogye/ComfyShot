//
//  ComfyShotInputBridge.swift
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
final class ComfyShotInputBridge {
    /// Mouse-down chooses one operation for the complete drag. The start point is
    /// retained because `CaptureAreaModel` expects translation from drag start.
    private enum DragOperation {
        case drawing
        case moving(startPoint: CGPoint)
        case resizing(edge: CaptureResizeEdge, startPoint: CGPoint)
    }

    private enum SelectionGridRegion {
        case resize(CaptureResizeEdge)
        case center
    }

    private let inputInterceptor = CaptureInputInterceptor()
    private let cursorController = SystemCursorController()
    private var overlayContexts: [OverlayContext] = []
    private var panelsWithDisabledCursorRects: [NSPanel] = []

    /// A drag stays attached to the display where it began.
    private var activeInputContext: OverlayContext?
    private var dragOperation: DragOperation?
    private var lastPointerLocation: CGPoint?

    /// These sizes mirror `SelectionRect` so both input paths resize identically.
    private let edgeHitWidth: CGFloat = 8
    private let cornerHitSize: CGFloat = 18

    private var isShiftHeld: Bool = false

    /// Starts isolated input and returns whether the event tap became active.
    ///
    /// When this succeeds, the tap consumes input before the foreground app or
    /// Dock receives it, preserving their last menu and hover state.
    @discardableResult
    func start(
        contexts: [OverlayContext],
        onCancel: @escaping () -> Void,
        onClearSelection: @escaping () -> Void,
    ) -> Bool {
        overlayContexts = contexts

        let didStart = inputInterceptor.start(
            mouseDown: { [weak self] in self?.handleMouseDown(at: $0) },
            mouseMoved: { [weak self] in self?.handleMouseMoved(to: $0) },
            mouseDragged: { [weak self] in self?.handleMouseDragged(to: $0) },
            mouseUp: { [weak self] in self?.handleMouseUp(at: $0) },
            cancel: onCancel,
            clearSelection: onClearSelection,
            isShiftHeld: { [weak self] held in
                self?.isShiftHeld = held
                if let point = self?.lastPointerLocation {
                    self?.updateCursor(at: point)
                }
            },
            capture: { [weak self] in self?.captureSelectedRect() }
        )

        if didStart {
            for context in overlayContexts where context.panel.areCursorRectsEnabled {
                context.panel.disableCursorRects()
                panelsWithDisabledCursorRects.append(context.panel)
            }
            let pointerLocation = NSEvent.mouseLocation
            lastPointerLocation = pointerLocation
            updateCursor(at: pointerLocation)
        } else {
            print("Capture input interceptor could not start. Accessibility/Input Monitoring permission may be required.")
        }
        return didStart
    }

    /// Ends input interception and clears every piece of session-only state.
    func stop() {
        inputInterceptor.stop()
        cursorController.stop()
        for panel in panelsWithDisabledCursorRects {
            panel.enableCursorRects()
        }
        panelsWithDisabledCursorRects = []
        overlayContexts = []
        activeInputContext = nil
        dragOperation = nil
        lastPointerLocation = nil
        isShiftHeld = false
    }

    /// Restores the capture cursor after the panels install their cursor rects.
    func refreshCursor() {
        updateCursor(at: lastPointerLocation ?? NSEvent.mouseLocation, force: true)
    }
}

// MARK: - Drag Input
extension ComfyShotInputBridge {
    /// Chooses whether this drag draws, moves, or resizes a selection.
    private func handleMouseDown(at globalPoint: CGPoint) {
        lastPointerLocation = globalPoint

        // Find the overlay under the global mouse position and convert the point
        // into that panel's local coordinates for selection hit testing.
        guard let context = overlayContext(containing: globalPoint),
              let localPoint = localOverlayPoint(for: globalPoint, in: context.panel) else {
            // The click landed outside every overlay, so there is no active drag.
            activeInputContext = nil
            dragOperation = nil
            return
        }

        // Keep this overlay as the owner of the drag, even if the pointer crosses displays.
        activeInputContext = context

        // Without a selection, an ordinary click starts drawing one.
        guard let selectionRect = context.model.selectionRect else {
            if !isShiftHeld {
                beginDrawing(at: localPoint, in: context)
            }
            return
        }

        if isShiftHeld {
            // Divide the selection into thirds on each axis. The eight outer
            // cells resize; the center moves; clicks outside do nothing.
            switch selectionGridRegion(at: localPoint, in: selectionRect) {
            case .resize(let edge):
                dragOperation = .resizing(edge: edge, startPoint: localPoint)
                cursorController.setCursor(.resize(edge))
            case .center:
                dragOperation = .moving(startPoint: localPoint)
                cursorController.setCursor(.closedHand)
            case nil:
                dragOperation = nil
            }
        } else {
            // Prefer resizing at an edge, then moving from inside the selection;
            // clicks elsewhere start a new selection.
            // A click on a resize handle starts resizing from that edge.
            if let edge = resizeEdge(at: localPoint, in: selectionRect) {
                dragOperation = .resizing(edge: edge, startPoint: localPoint)
                cursorController.setCursor(.resize(edge))
                // A click inside the selection starts moving it.
            } else if selectionRect.contains(localPoint) {
                dragOperation = .moving(startPoint: localPoint)
                cursorController.setCursor(.closedHand)
                // A click outside the selection starts drawing a replacement.
            } else {
                beginDrawing(at: localPoint, in: context)
            }
        }
    }

    private func handleMouseMoved(to globalPoint: CGPoint) {
        lastPointerLocation = globalPoint
        updateCursor(at: globalPoint)
    }

    /// Applies cumulative translation from the original mouse-down point.
    private func handleMouseDragged(to globalPoint: CGPoint) {
        lastPointerLocation = globalPoint
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
        lastPointerLocation = globalPoint
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
extension ComfyShotInputBridge {
    private func updateCursor(at globalPoint: CGPoint, force: Bool = false) {
        if let dragOperation {
            switch dragOperation {
            case .drawing:
                cursorController.setCursor(.crosshair, force: force)
            case .moving:
                cursorController.setCursor(.closedHand, force: force)
            case .resizing(let edge, _):
                cursorController.setCursor(.resize(edge), force: force)
            }
            return
        }
        guard let context = overlayContext(containing: globalPoint),
              let localPoint = localOverlayPoint(for: globalPoint, in: context.panel),
              let selectionRect = context.model.selectionRect else {
            cursorController.setCursor(.crosshair, force: force)
            return
        }

        if isShiftHeld {
            switch selectionGridRegion(at: localPoint, in: selectionRect) {
            case .resize(let edge): cursorController.setCursor(.resize(edge), force: force)
            case .center: cursorController.setCursor(.openHand, force: force)
            case nil: cursorController.setCursor(.crosshair, force: force)
            }
        } else if let edge = resizeEdge(at: localPoint, in: selectionRect) {
            cursorController.setCursor(.resize(edge), force: force)
        } else if selectionRect.contains(localPoint) {
            cursorController.setCursor(.openHand, force: force)
        } else {
            cursorController.setCursor(.crosshair, force: force)
        }
    }
}

// MARK: - Selection Hit Testing
extension ComfyShotInputBridge {
    /// Finds one of nine equal cells within the selection. Coordinates in the
    /// overlay increase downward, so row zero is the top row.
    private func selectionGridRegion(at point: CGPoint, in rect: CGRect) -> SelectionGridRegion? {
        guard rect.width > 0, rect.height > 0,
              rect.minX...rect.maxX ~= point.x,
              rect.minY...rect.maxY ~= point.y else { return nil }

        let column = point.x < rect.minX + rect.width / 3 ? 0
            : point.x < rect.minX + rect.width * 2 / 3 ? 1 : 2
        let row = point.y < rect.minY + rect.height / 3 ? 0
            : point.y < rect.minY + rect.height * 2 / 3 ? 1 : 2

        switch (row, column) {
        case (0, 0): return .resize(.topLeading)
        case (0, 1): return .resize(.top)
        case (0, 2): return .resize(.topTrailing)
        case (1, 0): return .resize(.leading)
        case (1, 1): return .center
        case (1, 2): return .resize(.trailing)
        case (2, 0): return .resize(.bottomLeading)
        case (2, 1): return .resize(.bottom)
        case (2, 2): return .resize(.bottomTrailing)
        default: return nil
        }
    }

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
extension ComfyShotInputBridge {
    /// Enter captures the first display that currently owns a selection.
    private func captureSelectedRect() {
        guard let context = overlayContexts.first(where: { $0.model.selectionRect != nil }) else {
            return
        }
        context.model.captureSelection()
    }
}

// MARK: - Coordinate Conversion
extension ComfyShotInputBridge {
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
