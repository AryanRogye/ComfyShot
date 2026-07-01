//
//  SelectionOverlay.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import SwiftUI

struct SelectionOverlay: View {
    @Bindable var model: CaptureAreaModel

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onExitCommand(perform: model.exit)
    }
    
    private var dimmedBackground: some View {
        GeometryReader { proxy in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: proxy.size))
                
                if let rect = model.selectionRect {
                    path.addRect(rect)
                }
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                model.beginDrag(at: value.startLocation)
                model.updateDrag(to: value.location)
            }
            .onEnded { value in
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
            .accessibilityLabel("Take A Capture Of The Selected Area")

            Button(action: model.exit) {
                Image(systemName: "xmark")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close Selection Overlay")
        }
        .padding()
    }
}
