//
//  SelectionOverlay.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import AppKit
import SwiftUI

struct SelectionOverlay: View {
    @Bindable var model: CaptureAreaModel
    @Bindable var defaultsManager: DefaultsManager

    var body: some View {
        ZStack {
            dimmedBackground

            if let rect = model.selectionRect {
                SelectionRect(
                    model: model,
                    rect: rect,
                    sizeText: model.selectionSizeText
                )
            }

            VStack {
                topRow
                Spacer()
            }

            virtualCursor
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onExitCommand(perform: model.exit)
    }

    @ViewBuilder
    private var virtualCursor: some View {
        if let location = model.virtualCursorLocation {
            let cursor = NSCursor.crosshair
            let imageSize = cursor.image.size

            /// Position the cursor by its hotspot rather than its image center so
            /// clicks and selection edges line up with the visible crosshair.
            Image(nsImage: cursor.image)
                .position(
                    x: location.x + imageSize.width / 2 - cursor.hotSpot.x,
                    y: location.y + imageSize.height / 2 - cursor.hotSpot.y
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
    
    private var dimmedBackground: some View {
        GeometryReader { proxy in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: proxy.size))
                
                if let rect = model.selectionRect {
                    path.addRect(rect)
                }
            }
            .fill(Color.black.opacity(defaultsManager.selectionRectOpacity), style: FillStyle(eoFill: true))
        }
    }

    private let minimumSelectionDragDistance: CGFloat = 6
    
    @State private var didCaptureGestureStart = false
    @State private var gestureStartSelectionRect: CGRect?
    @State private var isDrawingNewSelection = false
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !didCaptureGestureStart {
                    didCaptureGestureStart = true
                    gestureStartSelectionRect = model.selectionRect
                    isDrawingNewSelection = false
                }
                
                if isDrawingNewSelection {
                    model.updateDrag(to: value.location)
                    return
                }
                
                if let existingRect = gestureStartSelectionRect,
                   existingRect.width > 0,
                   existingRect.height > 0 {
                    
                    // If drag started inside the selected rect, don't create a new selection.
                    // This lets your move/resize flow own that interaction.
                    if existingRect.contains(value.startLocation) {
                        return
                    }
                    
                    // If there already is a selection, require intent before replacing it.
                    let distance = hypot(value.translation.width, value.translation.height)
                    
                    guard distance >= minimumSelectionDragDistance else {
                        return
                    }
                }
                
                // No existing selection? Start immediately.
                // Existing selection outside rect? Start only after threshold.
                model.beginDrag(at: value.startLocation)
                model.updateDrag(to: value.location)
                isDrawingNewSelection = true
            }
            .onEnded { value in
                defer {
                    didCaptureGestureStart = false
                    gestureStartSelectionRect = nil
                    isDrawingNewSelection = false
                }
                
                guard isDrawingNewSelection else {
                    return
                }
                
                model.endDrag(at: value.location)
            }
    }

    private var topRow: some View {
        HStack {
            if let sizeText = model.selectionSizeText {
                Text(sizeText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6))
                    .cornerRadius(6)
                    .padding(6)
            }

            Spacer()

            Button(action: model.captureSelection) {
                Text("Capture")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)

            Button(action: model.exit) {
                Image(systemName: "xmark")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }
}
