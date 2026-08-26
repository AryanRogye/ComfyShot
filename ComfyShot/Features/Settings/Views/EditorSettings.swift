//
//  EditorSettings.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/18/26.
//

import SwiftUI
import DrawKit

struct EditorSettings: View {
    
    @Bindable var defaultsManager: DefaultsManager
    
    var body: some View {
        Form {
            Section("Default Editor Behavior") {
                Section("Rectangle") {
                    RectangleDefaultSelectionCornerRadiusView(
                        rectangleDefaultSelection: defaultsManager.editorDefaultSelection.rectSelection
                    )
                    RectangleDefaultSelectionStrokeWidthView(
                        rectangleDefaultSelection: defaultsManager.editorDefaultSelection.rectSelection
                    )
                    RectangleDefaultSelectionStrokeColorView(
                        rectangleDefaultSelection: defaultsManager.editorDefaultSelection.rectSelection
                    )
                    RectangleDefaultSelectionOverrideColorView(
                        rectangleDefaultSelection: defaultsManager.editorDefaultSelection.rectSelection
                    )
                }
                Section("Circle") {
                    CircleDefaultSelectionStrokeWidthView(
                        circleDefaultSelection: defaultsManager.editorDefaultSelection.circleSelection
                    )
                    CircleDefaultSelectionStrokeColorView(
                        circleDefaultSelection: defaultsManager.editorDefaultSelection.circleSelection
                    )
                    CircleDefaultSelectionOverrideColorView(
                        circleDefaultSelection: defaultsManager.editorDefaultSelection.circleSelection
                    )
                }
                Section("Triangle") {
                    TriangleDefaultSelectionCornerRadiusView(
                        triangleDefaultSelection: defaultsManager.editorDefaultSelection.triangleSelection
                    )
                    TriangleDefaultSelectionStrokeWidthView(
                        triangleDefaultSelection: defaultsManager.editorDefaultSelection.triangleSelection
                    )
                    TriangleDefaultSelectionStrokeColorView(
                        triangleDefaultSelection: defaultsManager.editorDefaultSelection.triangleSelection
                    )
                    TriangleDefaultSelectionOverrideColorView(
                        triangleDefaultSelection: defaultsManager.editorDefaultSelection.triangleSelection
                    )
                }
                Section("Arrow") {
                    ArrowDefaultSelectionCornerRadiusView(
                        arrowDefaultSelection: defaultsManager.editorDefaultSelection.arrowSelection
                    )
                    ArrowDefaultSelectionStrokeWidthView(
                        arrowDefaultSelection: defaultsManager.editorDefaultSelection.arrowSelection
                    )
                    ArrowDefaultSelectionStrokeColorView(
                        arrowDefaultSelection: defaultsManager.editorDefaultSelection.arrowSelection
                    )
                    ArrowDefaultSelectionOverrideColorView(
                        arrowDefaultSelection: defaultsManager.editorDefaultSelection.arrowSelection
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    }
}
