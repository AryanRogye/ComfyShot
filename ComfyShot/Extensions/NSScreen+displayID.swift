//
//  NSScreen+displayID.swift
//  ComfyTile
//
//  Created by Aryan Rogye on 5/24/26.
//

import AppKit

extension NSScreen {
    nonisolated var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
