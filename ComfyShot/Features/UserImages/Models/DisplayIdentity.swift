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

    init?(screen: NSScreen) {
        guard let displayID = screen.displayID else { return nil }

        let vendorNumber = CGDisplayVendorNumber(displayID)
        let modelNumber = CGDisplayModelNumber(displayID)
        let serialNumber = CGDisplaySerialNumber(displayID)

        if vendorNumber != 0 || modelNumber != 0 || serialNumber != 0 {
            rawValue = "\(vendorNumber)-\(modelNumber)-\(serialNumber)"
        } else {
            rawValue = "display-\(displayID)"
        }
    }
}
