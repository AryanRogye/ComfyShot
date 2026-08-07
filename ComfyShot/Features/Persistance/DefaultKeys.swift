//
//  DefaultKeys.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import Defaults
import Foundation

extension Defaults.Keys {
    static let captureOverAppleScreenshotUI = Key<Bool>("captureOverAppleScreenshotUI", default: false)
    static let selectionRectOpacity = Key<CGFloat>("selection_rect_opacity", default: 0.9)
}
