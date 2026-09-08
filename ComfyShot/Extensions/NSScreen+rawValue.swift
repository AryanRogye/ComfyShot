//
//  NSScreen+rawValue.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/8/26.
//

import Cocoa

extension NSScreen {

    nonisolated var rawValue: String? {
        guard let displayID = displayID else { return nil }

        let vendorNumber = CGDisplayVendorNumber(displayID)
        let modelNumber = CGDisplayModelNumber(displayID)
        let serialNumber = CGDisplaySerialNumber(displayID)

        if vendorNumber != 0 || modelNumber != 0 || serialNumber != 0 {
            return "\(vendorNumber)-\(modelNumber)-\(serialNumber)"
        } else {
            return "display-\(displayID)"
        }
    }
}

