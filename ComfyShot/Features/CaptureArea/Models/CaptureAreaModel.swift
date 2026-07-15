//
//  CaptureAreaModel.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import CoreGraphics
import Observation

@Observable
@MainActor
final class CaptureAreaModel {

    var dragStart: CGPoint?
    var dragCurrent: CGPoint?
    private var initialMoveStart: CGPoint?
    private var initialMoveCurrent: CGPoint?
    private var initialResizeRect: CGRect?
    private let minimumSelectionLength: CGFloat = 1
    
    var capture: ((CGRect) -> Void)?
    var onExit: (() -> Void)?
    var onSelectionBegan: (() -> Void)?

    var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }

        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }

    var selectionSizeText: String? {
        guard let rect = selectionRect, rect.width > 0, rect.height > 0 else { return nil }
        return "\(Int(rect.width)) X \(Int(rect.height))"
    }

    func exit() {
        onExit?()
    }

    func captureSelection() {
        guard let capture else { return }

        if let rect = selectionRect, rect.width > 0, rect.height > 0 {
            capture(rect)
        }
    }

    func beginDrag(at point: CGPoint) {
        onSelectionBegan?()
        dragStart = point
        dragCurrent = point
    }

    func updateDrag(to point: CGPoint) {
        dragCurrent = point
    }

    func endDrag(at point: CGPoint) {
        dragCurrent = point
    }

    func clearSelection() {
        dragStart = nil
        dragCurrent = nil
    }

    func constrainSelection(to bounds: CGRect) {
        guard let selectionRect else { return }

        let constrainedRect = selectionRect.standardized.intersection(bounds.standardized)
        guard !constrainedRect.isNull,
              constrainedRect.width >= minimumSelectionLength,
              constrainedRect.height >= minimumSelectionLength else {
            clearSelection()
            return
        }

        dragStart = constrainedRect.origin
        dragCurrent = CGPoint(x: constrainedRect.maxX, y: constrainedRect.maxY)
    }
    
    func moveSelection(translation: CGSize) {
        // Capture the initial state on the first frame of the drag
        if initialMoveStart == nil {
            initialMoveStart = dragStart
            initialMoveCurrent = dragCurrent
        }
        
        // Apply the cumulative translation to both points
        if let start = initialMoveStart, let current = initialMoveCurrent {
            dragStart = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
            dragCurrent = CGPoint(x: current.x + translation.width, y: current.y + translation.height)
        }
    }
    
    func endMove() {
        // Reset so the next move starts fresh
        initialMoveStart = nil
        initialMoveCurrent = nil
    }

    func resizeSelection(edge: CaptureResizeEdge, translation: CGSize) {
        if initialResizeRect == nil {
            initialResizeRect = selectionRect
        }

        guard let initialResizeRect else { return }

        var minX = initialResizeRect.minX
        var maxX = initialResizeRect.maxX
        var minY = initialResizeRect.minY
        var maxY = initialResizeRect.maxY

        switch edge {
        case .top:
            minY = min(initialResizeRect.minY + translation.height, maxY - minimumSelectionLength)
        case .bottom:
            maxY = max(initialResizeRect.maxY + translation.height, minY + minimumSelectionLength)
        case .leading:
            minX = min(initialResizeRect.minX + translation.width, maxX - minimumSelectionLength)
        case .trailing:
            maxX = max(initialResizeRect.maxX + translation.width, minX + minimumSelectionLength)
        case .topLeading:
            minX = min(initialResizeRect.minX + translation.width, maxX - minimumSelectionLength)
            minY = min(initialResizeRect.minY + translation.height, maxY - minimumSelectionLength)
        case .topTrailing:
            maxX = max(initialResizeRect.maxX + translation.width, minX + minimumSelectionLength)
            minY = min(initialResizeRect.minY + translation.height, maxY - minimumSelectionLength)
        case .bottomLeading:
            minX = min(initialResizeRect.minX + translation.width, maxX - minimumSelectionLength)
            maxY = max(initialResizeRect.maxY + translation.height, minY + minimumSelectionLength)
        case .bottomTrailing:
            maxX = max(initialResizeRect.maxX + translation.width, minX + minimumSelectionLength)
            maxY = max(initialResizeRect.maxY + translation.height, minY + minimumSelectionLength)
        }

        dragStart = CGPoint(x: minX, y: minY)
        dragCurrent = CGPoint(x: maxX, y: maxY)
    }

    func endResize() {
        initialResizeRect = nil
    }
}
