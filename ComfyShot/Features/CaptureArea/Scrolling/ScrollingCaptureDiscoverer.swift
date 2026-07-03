//
//  ScrollingCaptureDiscoverer.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import AppKit
import ApplicationServices
import CoreGraphics

public struct ScrollTarget {
    let scrollbar: AXUIElement?
    let scrollArea: AXUIElement?
}

public struct TargetDiscovery {
    let point: CGPoint
    let hitElement: AXUIElement
    let target: ScrollTarget
}

public final class ScrollingCaptureDiscoverer {
    public init() {}

    public func discover(
        preferredTargetPoint: CGPoint,
        screen: NSScreen,
        rect: CGRect
    ) -> TargetDiscovery? {
        for point in targetPointCandidates(
            preferredTargetPoint: preferredTargetPoint,
            screen: screen,
            rect: rect
        ) {
            guard let hitElement = element(at: point),
                  let target = scrollTarget(startingAt: hitElement)
            else {
                continue
            }

            return TargetDiscovery(
                point: point,
                hitElement: hitElement,
                target: target
            )
        }

        return nil
    }
}

private extension ScrollingCaptureDiscoverer {
    func targetPointCandidates(
        preferredTargetPoint: CGPoint,
        screen: NSScreen,
        rect: CGRect
    ) -> [CGPoint] {
        let rect = rect.standardized
        let displayBounds: CGRect
        if let displayID = screen.displayID {
            displayBounds = CGDisplayBounds(displayID)
        } else {
            displayBounds = screen.frame
        }

        return uniquePoints([
            preferredTargetPoint,
            CGPoint(
                x: displayBounds.minX + rect.midX,
                y: displayBounds.minY + rect.midY
            ),
            CGPoint(
                x: displayBounds.minX + rect.midX,
                y: displayBounds.minY + max(0, displayBounds.height - rect.midY)
            )
        ])
    }

    func uniquePoints(_ points: [CGPoint]) -> [CGPoint] {
        points.reduce(into: [CGPoint]()) { result, point in
            let alreadyIncluded = result.contains {
                abs($0.x - point.x) < 0.5 && abs($0.y - point.y) < 0.5
            }

            if !alreadyIncluded {
                result.append(point)
            }
        }
    }

    func element(at targetPoint: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(targetPoint.x),
            Float(targetPoint.y),
            &element
        )

        return result == .success ? element : nil
    }

    func scrollTarget(startingAt element: AXUIElement) -> ScrollTarget? {
        var current: AXUIElement? = element

        for _ in 0..<40 {
            guard let element = current else { break }

            if isScrollArea(element) {
                if let scrollbar = element.axElementAttribute(kAXVerticalScrollBarAttribute as CFString),
                   isVerticalScrollbar(scrollbar) {
                    return ScrollTarget(scrollbar: scrollbar, scrollArea: element)
                }

                return ScrollTarget(scrollbar: nil, scrollArea: element)
            }

            if isVerticalScrollbar(element) {
                return ScrollTarget(
                    scrollbar: element,
                    scrollArea: nearestScrollArea(from: element)
                )
            }

            if let scrollbar = element.axElementAttribute(kAXVerticalScrollBarAttribute as CFString),
               isVerticalScrollbar(scrollbar) {
                return ScrollTarget(
                    scrollbar: scrollbar,
                    scrollArea: isScrollArea(element) ? element : nearestScrollArea(from: element)
                )
            }

            current = element.axElementAttribute(kAXParentAttribute as CFString)
        }

        return nil
    }

    func nearestScrollArea(from element: AXUIElement) -> AXUIElement? {
        var current = element.axElementAttribute(kAXParentAttribute as CFString)

        for _ in 0..<40 {
            guard let element = current else { break }

            if isScrollArea(element) {
                return element
            }

            current = element.axElementAttribute(kAXParentAttribute as CFString)
        }

        return nil
    }

    func isScrollArea(_ element: AXUIElement) -> Bool {
        element.stringAttribute(kAXRoleAttribute as CFString) == kAXScrollAreaRole as String
    }

    func isVerticalScrollbar(_ element: AXUIElement) -> Bool {
        guard element.stringAttribute(kAXRoleAttribute as CFString) == kAXScrollBarRole as String else {
            return false
        }

        if let orientation = element.stringAttribute(kAXOrientationAttribute as CFString) {
            return orientation == kAXVerticalOrientationValue as String
        }

        guard let size = element.sizeAttribute(kAXSizeAttribute as CFString) else {
            return true
        }

        return size.height >= size.width
    }
}
