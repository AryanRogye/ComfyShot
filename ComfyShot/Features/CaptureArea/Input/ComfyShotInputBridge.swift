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
/// moving it, resizing it, and drawing the virtual cursor.
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
            clearSelection: { [weak self] in
                onClearSelection()
                if let point = self?.lastPointerLocation {
                    self?.updateCursor(at: point)
                }
            },
            isShiftHeld: { [weak self] held in
                self?.isShiftHeld = held
                if let point = self?.lastPointerLocation {
                    self?.updateCursor(at: point)
                }
            },
            capture: { [weak self] in self?.captureSelectedRect() }
        )

        if didStart {
            CaptureCursorOverride.isIntercepting = true
            for context in overlayContexts {
                context.panel.discardCursorRects()
                if context.panel.areCursorRectsEnabled {
                    context.panel.disableCursorRects()
                    panelsWithDisabledCursorRects.append(context.panel)
                }
                if let contentView = context.panel.contentView {
                    contentView.discardCursorRects()
                    contentView.updateTrackingAreas()
                }
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
        for context in overlayContexts {
            context.model.virtualCursorLocation = nil
            context.model.virtualCursor = .crosshair
        }
        CaptureCursorOverride.isIntercepting = false
        for context in overlayContexts {
            context.panel.ignoresMouseEvents = false
        }
        for panel in panelsWithDisabledCursorRects {
            panel.enableCursorRects()
            if let contentView = panel.contentView {
                panel.invalidateCursorRects(for: contentView)
                contentView.updateTrackingAreas()
            }
        }
        panelsWithDisabledCursorRects = []
        overlayContexts = []
        activeInputContext = nil
        dragOperation = nil
        lastPointerLocation = nil
        isShiftHeld = false
    }

    /// Hides the hardware cursor after all overlay panels are visible.
    func hideSystemCursor() {
        inputInterceptor.hideSystemCursor()
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
                updateCursor(at: globalPoint)
            case .center:
                dragOperation = .moving(startPoint: localPoint)
                updateCursor(at: globalPoint)
            case nil:
                dragOperation = nil
            }
        } else {
            // Prefer resizing at an edge, then moving from inside the selection;
            // clicks elsewhere start a new selection.
            // A click on a resize handle starts resizing from that edge.
            if let edge = resizeEdge(at: localPoint, in: selectionRect) {
                dragOperation = .resizing(edge: edge, startPoint: localPoint)
                updateCursor(at: globalPoint)
                // A click inside the selection starts moving it.
            } else if selectionRect.contains(localPoint) {
                dragOperation = .moving(startPoint: localPoint)
                updateCursor(at: globalPoint)
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

// MARK: - Virtual Cursor
extension ComfyShotInputBridge {
    private func updateCursor(at globalPoint: CGPoint) {
        let shape: NSCursor
        if let dragOperation {
            switch dragOperation {
            case .drawing:
                shape = .crosshair
            case .moving:
                shape = .closedHand
            case .resizing(let edge, _):
                shape = CaptureCursorOverride.resizeCursor(for: edge)
            }
            drawCursor(shape, at: globalPoint)
            return
        }
        guard let context = overlayContext(containing: globalPoint),
              let localPoint = localOverlayPoint(for: globalPoint, in: context.panel),
              let selectionRect = context.model.selectionRect else {
            drawCursor(.crosshair, at: globalPoint)
            return
        }

        if isShiftHeld {
            switch selectionGridRegion(at: localPoint, in: selectionRect) {
            case .resize(let edge): shape = CaptureCursorOverride.resizeCursor(for: edge)
            case .center: shape = .openHand
            case nil: shape = .crosshair
            }
        } else if let edge = resizeEdge(at: localPoint, in: selectionRect) {
            shape = CaptureCursorOverride.resizeCursor(for: edge)
        } else if selectionRect.contains(localPoint) {
            shape = .openHand
        } else {
            shape = .crosshair
        }
        drawCursor(shape, at: globalPoint)
    }

    private func drawCursor(_ cursor: NSCursor, at globalPoint: CGPoint) {
        for context in overlayContexts {
            context.model.virtualCursorLocation = localOverlayPoint(for: globalPoint, in: context.panel)
            if context.model.virtualCursorLocation != nil {
                context.model.virtualCursor = cursor
            }
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
            let frame = $0.panel.frame
            return globalPoint.x >= frame.minX && globalPoint.x <= frame.maxX
                && globalPoint.y >= frame.minY && globalPoint.y <= frame.maxY
        }
    }

    /// Converts bottom-left global coordinates into top-left SwiftUI coordinates.
    private func localOverlayPoint(for globalPoint: CGPoint, in panel: NSPanel) -> CGPoint? {
        let frame = panel.frame
        guard globalPoint.x >= frame.minX && globalPoint.x <= frame.maxX
            && globalPoint.y >= frame.minY && globalPoint.y <= frame.maxY else { return nil }
        return CGPoint(
            x: globalPoint.x - frame.minX,
            y: frame.maxY - globalPoint.y
        )
    }
}
