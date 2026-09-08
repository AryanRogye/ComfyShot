//
//  DisplayIdentity.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 6/30/26.
//

import AppKit

/// Stable-enough display identity for mapping floating panels to physical screens.
struct DisplayIdentity: Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}
