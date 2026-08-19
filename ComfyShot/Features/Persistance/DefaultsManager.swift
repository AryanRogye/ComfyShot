//
//  DefaultsManager.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import Defaults
import Foundation
import DrawKit

@Observable
@MainActor
final class DefaultsManager {
    
    var captureOverAppleScreenshotUI: Bool = Defaults[.captureOverAppleScreenshotUI] {
        didSet {
            Defaults[.captureOverAppleScreenshotUI] = captureOverAppleScreenshotUI
        }
    }
    
    var selectionRectOpacity: CGFloat = Defaults[.selectionRectOpacity] {
        didSet {
            Defaults[.selectionRectOpacity] = selectionRectOpacity
        }
    }
    
    var editorDefaultSelection: DefaultSelection
    
    init() {
        self.editorDefaultSelection = Defaults[.editorDefaultSelection]
        
        observeEditorDefaults()
    }
    
    private func observeEditorDefaults() {
        withObservationTracking {
            _ = editorDefaultSelection.rectSelection.cornerRadius
            _ = editorDefaultSelection.rectSelection.strokeWidth
            _ = editorDefaultSelection.rectSelection.strokeColor
            _ = editorDefaultSelection.rectSelection.overrideColor
            
            _ = editorDefaultSelection.circleSelection.strokeWidth
            _ = editorDefaultSelection.circleSelection.strokeColor
            _ = editorDefaultSelection.circleSelection.overrideColor
            
            _ = editorDefaultSelection.triangleSelection.cornerRadius
            _ = editorDefaultSelection.triangleSelection.strokeWidth
            _ = editorDefaultSelection.triangleSelection.strokeColor
            _ = editorDefaultSelection.triangleSelection.overrideColor
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                Defaults[.editorDefaultSelection] = self.editorDefaultSelection
                
                self.observeEditorDefaults()
            }
        }
    }
}
