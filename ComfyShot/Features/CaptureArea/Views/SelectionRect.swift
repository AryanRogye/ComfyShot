//
//  SelectionRect.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import SwiftUI

#Preview {
    ZStack {
        Color.black.opacity(0.8).ignoresSafeArea()
        
        VStack {
            SelectionShape()
                .frame(width: 100, height: 100)
        }
        .frame(maxWidth: 200, maxHeight: 200)
    }
}

struct SelectionRect: View {
    @Bindable var model: CaptureAreaModel
    let rect: CGRect
    let sizeText: String?
    @State private var isHoveringSelection = false
    @State private var hoveredResizeEdge: CaptureResizeEdge?
    private let edgeHitWidth: CGFloat = 8
    private let cornerHitSize: CGFloat = 18

    var body: some View {
        ZStack {
            SelectionShape()
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringSelection = hovering
                    
                    if hovering {
                        CaptureCursorOverride.setOpenHand()
                    } else {
                        CaptureCursorOverride.clear()
                    }
                }
                .gesture(moveGesture)
            
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

            cornerHoverArea(.topLeading)
                .frame(width: cornerHitSize, height: cornerHitSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            cornerHoverArea(.topTrailing)
                .frame(width: cornerHitSize, height: cornerHitSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            cornerHoverArea(.bottomLeading)
                .frame(width: cornerHitSize, height: cornerHitSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            cornerHoverArea(.bottomTrailing)
                .frame(width: cornerHitSize, height: cornerHitSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private func edgeHoverArea(_ edge: CaptureResizeEdge) -> some View {
        resizeHoverArea(edge)
    }

    private func cornerHoverArea(_ edge: CaptureResizeEdge) -> some View {
        resizeHoverArea(edge)
    }

    private func resizeHoverArea(_ edge: CaptureResizeEdge) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    hoveredResizeEdge = edge
                    setResizeCursor(for: edge)
                } else if hoveredResizeEdge == edge {
                    hoveredResizeEdge = nil
                    CaptureCursorOverride.clear()
                } else {
                    return
                }
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

    private func resizeGesture(for edge: CaptureResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                setResizeCursor(for: edge)
                model.resizeSelection(
                    edge: edge,
                    translation: value.translation
                )
            }
            .onEnded { _ in
                model.endResize()

                if hoveredResizeEdge == edge {
                    setResizeCursor(for: edge)
                } else {
                    CaptureCursorOverride.clear()
                }
            }
    }

    private func setResizeCursor(for edge: CaptureResizeEdge) {
        switch edge {
        case .top, .bottom:
            CaptureCursorOverride.setResizeUpDown()
        case .leading, .trailing:
            CaptureCursorOverride.setResizeLeftRight()
        case .topLeading, .bottomTrailing:
            CaptureCursorOverride.setResizeTopLeftBottomRight()
        case .topTrailing, .bottomLeading:
            CaptureCursorOverride.setResizeTopRightBottomLeft()
        }
    }

    private var dragCircle: some View {
        Circle()
            .fill(.red)
            .frame(width: 7, height: 7)
    }
}

struct SelectionShape: View {
    
    private struct DashSegment {
        let from: CGPoint
        let to: CGPoint
        let color: Color
    }
    
    var primaryColor: Color {
        Color(red: 0.82, green: 0.82, blue: 0.84)
    }
    
    var secondaryColor: Color {
        Color.black
    }
    
    var strokeColor: Color {
        .white
    }
    
    var circleSize: CGFloat {
        6
    }
    
    var rectStrokeWidth: CGFloat {
        2
    }
    
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            
            
            
            /// Left
            dashedLine(
                from: CGPoint(x: rect.minX, y: rect.minY),
                to: CGPoint(x: rect.minX, y: rect.maxY),
                context: &context
            )
            
            /// Top
            dashedLine(
                from: CGPoint(x: rect.minX, y: rect.minY),
                to: CGPoint(x: rect.maxX, y: rect.minY),
                context: &context
            )
            
            /// right
            dashedLine(
                from: CGPoint(x: rect.maxX, y: rect.minY),
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                context: &context
            )
            
            /// Bottom
            dashedLine(
                from: CGPoint(x: rect.minX, y: rect.maxY),
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                context: &context
            )
            
            for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)] {
                let circlePath = Path(ellipseIn: CGRect(x: corner.x - circleSize/2, y: corner.y - circleSize/2, width: circleSize, height: circleSize))
                context.fill(circlePath, with: .color(primaryColor))
                context.stroke(circlePath, with: .color(strokeColor), lineWidth: 1)
            }
        }
    }
    
    
    private func line(from start: CGPoint, to end: CGPoint) -> some View {
        let segments = dashSegments(from: start, to: end)
        
        return ZStack {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                
                Path { path in
                    path.move(to: segment.from)
                    path.addLine(to: segment.to)
                }
                .stroke(segment.color, lineWidth: 1.1)
            }
        }
    }
    
    private func circle(at point: CGPoint) -> some View {
        Circle()
            .fill(primaryColor)
            .frame(
                width: circleSize,
                height: circleSize
            )
            .position(x: point.x, y: point.y)
            .overlay {
                Circle()
                    .stroke(
                        strokeColor,
                        style: .init(
                            lineWidth: 1
                        )
                    )
                    .frame(
                        width: circleSize,
                        height: circleSize
                    )
                    .position(x: point.x, y: point.y)
            }
    }
    
    private func dashedLine(from start: CGPoint, to end: CGPoint, context: inout GraphicsContext) {
        for segment in dashSegments(from: start, to: end) {
            var path = Path()
            path.move(to: segment.from)
            path.addLine(to: segment.to)
            context.stroke(path, with: .color(segment.color), lineWidth: 1.1)
        }
    }
    
    private func dashSegments(from start: CGPoint, to end: CGPoint) -> [DashSegment] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        
        guard length > 0 else {
            return []
        }
        
        let unitX = dx / length
        let unitY = dy / length
        
        func point(at distance: CGFloat) -> CGPoint {
            CGPoint(
                x: start.x + unitX * distance,
                y: start.y + unitY * distance
            )
        }
        
        var segments: [DashSegment] = []
        
        var distance: CGFloat = 0
        var index = 0
        
        let firstSegmentLength: CGFloat = 7
        let lastSegmentLength: CGFloat = 7
        let normalSegmentLength: CGFloat = 4
        
        let endOfNormalSegments = max(0, length - lastSegmentLength)
        
        while distance < endOfNormalSegments {
            let currentLength = index == 0 ? firstSegmentLength : normalSegmentLength
            
            let segmentStart = distance
            let segmentEnd = min(distance + currentLength, endOfNormalSegments)
            
            let color: Color = index.isMultiple(of: 2) ? .black : .white
            
            segments.append(
                DashSegment(
                    from: point(at: segmentStart),
                    to: point(at: segmentEnd),
                    color: color
                )
            )
            
            distance += currentLength
            index += 1
        }
        
        segments.append(
            DashSegment(
                from: point(at: endOfNormalSegments),
                to: point(at: length),
                color: .black
            )
        )
        
        
        return segments
    }
}
