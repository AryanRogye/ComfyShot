//
//  DefaultKeys.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import Defaults
import Foundation
import DrawKit

public struct DefaultSelectionBridge: Defaults.Bridge {
    
    public typealias Value = DefaultSelection
    public typealias Serializable = String
    
    public func serialize(_ value: DrawKit.DefaultSelection?) -> String? {
        return value?.asString()
    }
    
    public func deserialize(_ object: String?) -> DrawKit.DefaultSelection? {
        return DefaultSelection(fromString: object)
    }
}

extension DefaultSelection: Defaults.Serializable {
    public static let bridge = DefaultSelectionBridge()
}

extension Defaults.Keys {
    static let captureOverAppleScreenshotUI = Key<Bool>("captureOverAppleScreenshotUI", default: false)
    static let selectionRectOpacity = Key<CGFloat>("selection_rect_opacity", default: 0.9)
    static let editorDefaultSelection = Key<DefaultSelection>("editor_default_selection", default: .init())
}
