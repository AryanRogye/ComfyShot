//
//  DefaultsManager.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import Defaults
import Foundation

@Observable
@MainActor
final class DefaultsManager {
    
    var captureOverAppleScreenshotUI: Bool = Defaults[.captureOverAppleScreenshotUI] {
        didSet {
            Defaults[.captureOverAppleScreenshotUI] = captureOverAppleScreenshotUI
        }
    }
}
