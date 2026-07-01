//
//  SelectionRect.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import SwiftUI

struct SelectionRect: View {
    @Bindable var model: CaptureAreaModel
    let rect: CGRect
    let sizeText: String?
    @State private var isHoveringSelection = false
    @State private var hoveredEdge: Edge?
    private let edgeHitWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .onHover { hovering in
                    isHoveringSelection = hovering

                    if hovering {
                        CaptureCursorOverride.setOpenHand()
                    } else {
                        CaptureCursorOverride.clear()
                    }
                }
                .gesture(moveGesture)

            Rectangle()
                .stroke(.white, lineWidth: 2)
                .allowsHitTesting(false)

            edgeHoverAreas
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private var edgeHoverAreas: some View {
        ZStack {
            edgeHoverArea(.top)
                .frame(height: edgeHitWidth)
                .frame(maxHeight: .infinity, alignment: .top)

            edgeHoverArea(.bottom)
                .frame(height: edgeHitWidth)
                .frame(maxHeight: .infinity, alignment: .bottom)

            edgeHoverArea(.leading)
                .frame(width: edgeHitWidth)
                .frame(maxWidth: .infinity, alignment: .leading)

            edgeHoverArea(.trailing)
                .frame(width: edgeHitWidth)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func edgeHoverArea(_ edge: Edge) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onHover { hovering in
                hoveredEdge = hovering ? edge : nil
                if hoveredEdge == .top || hoveredEdge == .bottom {
                    CaptureCursorOverride.setResizeUpDown()
                }
                else if hoveredEdge == .leading || hoveredEdge == .trailing {
                    CaptureCursorOverride.setResizeLeftRight()
                } else {
                    CaptureCursorOverride.clear()
                }
                print("Hovering Over Stroke: \(hovering)")
            }
            .gesture(resizeGesture(for: edge))
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                CaptureCursorOverride.setClosedHand()
                model.moveSelection(translation: value.translation)
            }
            .onEnded { _ in
                if isHoveringSelection {
                    CaptureCursorOverride.setOpenHand()
                } else {
                    CaptureCursorOverride.clear()
                }

                model.endMove()
            }
    }

    private func resizeGesture(for edge: Edge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                setResizeCursor(for: edge)
                model.resizeSelection(
                    edge: captureResizeEdge(for: edge),
                    translation: value.translation
                )
            }
            .onEnded { _ in
                model.endResize()

                if hoveredEdge == edge {
                    setResizeCursor(for: edge)
                } else {
                    CaptureCursorOverride.clear()
                }
            }
    }

    private func setResizeCursor(for edge: Edge) {
        if edge == .top || edge == .bottom {
            CaptureCursorOverride.setResizeUpDown()
        } else {
            CaptureCursorOverride.setResizeLeftRight()
        }
    }

    private func captureResizeEdge(for edge: Edge) -> CaptureResizeEdge {
        switch edge {
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }

    private var dragCircle: some View {
        Circle()
            .fill(.red)
            .frame(width: 7, height: 7)
    }
}
