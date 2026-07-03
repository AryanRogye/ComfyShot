//
//  AXUIElement+ScrollingCapture.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import AppKit
import ApplicationServices

extension AXUIElement {
    func copyAttribute(_ attribute: CFString) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute, &value)
        return result == .success ? value : nil
    }

    func axElementAttribute(_ attribute: CFString) -> AXUIElement? {
        guard let value = copyAttribute(attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return (value as! AXUIElement)
    }

    func stringAttribute(_ attribute: CFString) -> String? {
        copyAttribute(attribute) as? String
    }

    func numberAttribute(_ attribute: CFString) -> Double? {
        guard let value = copyAttribute(attribute) else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String {
            return Double(string)
        }

        return nil
    }

    func sizeAttribute(_ attribute: CFString) -> CGSize? {
        guard let value = copyAttribute(attribute),
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    func childElements() -> [AXUIElement] {
        let attributes = [
            kAXVisibleChildrenAttribute as CFString,
            kAXChildrenAttribute as CFString
        ]

        for attribute in attributes {
            if let children = copyAttribute(attribute) as? [AXUIElement],
               !children.isEmpty {
                return children
            }
        }

        return []
    }

    func isAttributeSettable(_ attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(self, attribute, &settable)
        return result == .success && settable.boolValue
    }

    func setNumberAttribute(_ value: Double, _ attribute: CFString) -> Bool {
        let result = AXUIElementSetAttributeValue(
            self,
            attribute,
            NSNumber(value: value)
        )

        return result == .success
    }

    func performAction(_ action: CFString) -> Bool {
        AXUIElementPerformAction(self, action) == .success
    }

    func activateOwningApplication() {
        var pid = pid_t()
        let result = AXUIElementGetPid(self, &pid)
        guard result == .success,
              pid != NSRunningApplication.current.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid)
        else {
            return
        }

        app.activate()
    }
}
