//
//  ScrollingCaptureService.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import AppKit
import ApplicationServices
import CoreGraphics
import SnapCore

public struct ScrollingCaptureConfiguration {
    public var maxFrames: Int
    public var settleDelayNanoseconds: UInt64
    public var actionStepDelayNanoseconds: UInt64
    public var viewportStepRatio: Double
    public var gapTolerancePixels: Int
    public var maxActionAttemptsPerFrame: Int
    public var eventScrollDeltaPixels: Int32
    public var maxEventAttemptsPerFrame: Int

    public nonisolated static let `default` = Self(
        maxFrames: 80,
        settleDelayNanoseconds: 180_000_000,
        actionStepDelayNanoseconds: 35_000_000,
        viewportStepRatio: 0.72,
        gapTolerancePixels: 2,
        maxActionAttemptsPerFrame: 36,
        eventScrollDeltaPixels: 240,
        maxEventAttemptsPerFrame: 12
    )

    public init(
        maxFrames: Int,
        settleDelayNanoseconds: UInt64,
        actionStepDelayNanoseconds: UInt64,
        viewportStepRatio: Double,
        gapTolerancePixels: Int,
        maxActionAttemptsPerFrame: Int,
        eventScrollDeltaPixels: Int32,
        maxEventAttemptsPerFrame: Int
    ) {
        self.maxFrames = maxFrames
        self.settleDelayNanoseconds = settleDelayNanoseconds
        self.actionStepDelayNanoseconds = actionStepDelayNanoseconds
        self.viewportStepRatio = viewportStepRatio
        self.gapTolerancePixels = gapTolerancePixels
        self.maxActionAttemptsPerFrame = maxActionAttemptsPerFrame
        self.eventScrollDeltaPixels = eventScrollDeltaPixels
        self.maxEventAttemptsPerFrame = maxEventAttemptsPerFrame
    }
}

public enum ScrollingCaptureResult {
    case success(CGImage)
    case partial(CGImage, reason: ScrollingCaptureStopReason)
    case failure(ScrollingCaptureFailure)
}

public enum ScrollingCaptureStopReason {
    case reachedEnd
    case maxFramesReached
    case cancelled
}

public enum ScrollingCaptureFailure: Error {
    case accessibilityPermissionDenied
    case noElementAtSelectionCenter
    case unsupportedScrollableTarget
    case scrollPositionUnavailable
    case captureFailed
    case stitchingFailed
}

@MainActor
public final class ScrollingCaptureService {
    private let screenshot: any ScreenshotProviding

    public init(screenshot: any ScreenshotProviding) {
        self.screenshot = screenshot
    }

    public func capture(
        screen: NSScreen,
        rect: CGRect,
        targetPoint: CGPoint,
        configuration: ScrollingCaptureConfiguration = .default
    ) async -> ScrollingCaptureResult {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityPermissionDenied)
        }

        guard let discovery = discoverScrollTarget(
            preferredTargetPoint: targetPoint,
            screen: screen,
            rect: rect
        ) else {
            return .failure(.noElementAtSelectionCenter)
        }

        activateOwningApplication(for: discovery.hitElement)

        guard let scrollbar = discovery.target.scrollbar else {
            return await captureWithEventsOnly(
                screen: screen,
                rect: rect,
                targetPoint: discovery.point,
                configuration: configuration
            )
        }

        let canSetScrollValue = isAttributeSettable(scrollbar, kAXValueAttribute as CFString)
        guard let initialMetrics = scrollMetrics(for: scrollbar),
              initialMetrics.hasUsableScrollRange
        else {
            return .failure(.scrollPositionUnavailable)
        }

        guard let startMetrics = await moveToStartingEdge(
            target: discovery.target,
            targetPoint: discovery.point,
            initialMetrics: initialMetrics,
            canSetScrollValue: canSetScrollValue,
            configuration: configuration
        ),
              let firstFrame = await captureFrame(screen: screen, rect: rect)
        else {
            return .failure(.captureFailed)
        }

        let layout = ScrollLayout(
            metrics: startMetrics,
            captureRect: rect,
            firstFrame: firstFrame
        )
        guard layout.isUsable else {
            return .failure(.scrollPositionUnavailable)
        }

        var frames = [
            PositionedFrame(
                image: firstFrame,
                y: 0
            )
        ]
        var currentOffsetPoints = layout.offsetPoints(for: startMetrics.value)
        let startingOffsetPoints = currentOffsetPoints
        let stepPoints = max(1, rect.height * CGFloat(configuration.viewportStepRatio))
        var stopReason = ScrollingCaptureStopReason.reachedEnd

        for _ in 1..<max(1, configuration.maxFrames) {
            if Task.isCancelled {
                stopReason = .cancelled
                break
            }

            let requestedOffsetPoints = min(
                layout.maximumOffsetPoints,
                currentOffsetPoints + stepPoints
            )

            guard requestedOffsetPoints > currentOffsetPoints + layout.minimumMovementPoints else {
                stopReason = .reachedEnd
                break
            }

            guard let currentMetrics = await moveTowardOffset(
                requestedOffsetPoints,
                from: currentOffsetPoints,
                layout: layout,
                target: discovery.target,
                targetPoint: discovery.point,
                canSetScrollValue: canSetScrollValue,
                configuration: configuration
            ) else {
                return .failure(.scrollPositionUnavailable)
            }

            let actualOffsetPoints = layout.offsetPoints(for: currentMetrics.value)
            guard actualOffsetPoints > currentOffsetPoints + layout.minimumMovementPoints else {
                stopReason = .reachedEnd
                break
            }

            guard let image = await captureFrame(screen: screen, rect: rect) else {
                return .failure(.captureFailed)
            }

            frames.append(PositionedFrame(
                image: image,
                y: layout.pixelOffset(forOffsetPoints: actualOffsetPoints - startingOffsetPoints)
            ))

            currentOffsetPoints = actualOffsetPoints

            if currentMetrics.value >= currentMetrics.maxValue - layout.valueEpsilon {
                stopReason = .reachedEnd
                break
            }
        }

        if frames.count >= max(1, configuration.maxFrames) {
            stopReason = .maxFramesReached
        }

        return finish(frames: frames, stopReason: stopReason, configuration: configuration)
    }
}

private extension ScrollingCaptureService {
    enum ScrollDirection {
        case backward
        case forward

        var valueAction: CFString {
            switch self {
            case .backward:
                return kAXDecrementAction as CFString
            case .forward:
                return kAXIncrementAction as CFString
            }
        }

        var pageSubrole: String {
            switch self {
            case .backward:
                return kAXDecrementPageSubrole as String
            case .forward:
                return kAXIncrementPageSubrole as String
            }
        }

        var arrowSubrole: String {
            switch self {
            case .backward:
                return kAXDecrementArrowSubrole as String
            case .forward:
                return kAXIncrementArrowSubrole as String
            }
        }
    }

    struct ScrollTarget {
        let scrollbar: AXUIElement?
        let scrollArea: AXUIElement?
    }

    struct ScrollMetrics {
        let value: Double
        let minValue: Double
        let maxValue: Double
        let visibleFraction: Double
        let trackHeight: CGFloat

        var hasUsableScrollRange: Bool {
            maxValue > minValue && visibleFraction > 0 && visibleFraction <= 1 && trackHeight > 0
        }
    }

    struct ScrollLayout {
        let minValue: Double
        let maxValue: Double
        let valueRange: Double
        let maximumOffsetPoints: CGFloat
        let pointToPixelScale: CGFloat

        init(metrics: ScrollMetrics, captureRect: CGRect, firstFrame: CGImage) {
            minValue = metrics.minValue
            maxValue = metrics.maxValue
            valueRange = metrics.maxValue - metrics.minValue
            maximumOffsetPoints = max(
                0,
                metrics.trackHeight / CGFloat(metrics.visibleFraction) - metrics.trackHeight
            )
            pointToPixelScale = max(1, CGFloat(firstFrame.height) / max(1, captureRect.height))
        }

        var isUsable: Bool {
            valueRange > 0 && maximumOffsetPoints >= 0 && pointToPixelScale > 0
        }

        var valueEpsilon: Double {
            max(valueRange * 0.0005, 0.0001)
        }

        var minimumMovementPoints: CGFloat {
            max(0.5, 1 / pointToPixelScale)
        }

        func offsetPoints(for value: Double) -> CGFloat {
            let normalized = (value - minValue) / valueRange
            return CGFloat(max(0, min(1, normalized))) * maximumOffsetPoints
        }

        func value(forOffsetPoints offset: CGFloat) -> Double {
            guard maximumOffsetPoints > 0 else { return minValue }

            let normalized = Double(max(0, min(maximumOffsetPoints, offset)) / maximumOffsetPoints)
            return minValue + normalized * valueRange
        }

        func pixelOffset(forOffsetPoints offset: CGFloat) -> Int {
            max(0, Int((offset * pointToPixelScale).rounded()))
        }
    }

    struct PositionedFrame {
        let image: CGImage
        let y: Int

        var width: Int {
            image.width
        }

        var height: Int {
            image.height
        }
    }

    struct StitchPiece {
        let image: CGImage
        let visualY: Int
        let height: Int
    }

    struct TargetDiscovery {
        let point: CGPoint
        let hitElement: AXUIElement
        let target: ScrollTarget
    }

    func discoverScrollTarget(
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

    func captureWithEventsOnly(
        screen: NSScreen,
        rect: CGRect,
        targetPoint: CGPoint,
        configuration: ScrollingCaptureConfiguration
    ) async -> ScrollingCaptureResult {
        guard let firstFrame = await captureFrame(screen: screen, rect: rect) else {
            return .failure(.captureFailed)
        }

        let pointToPixelScale = max(1, CGFloat(firstFrame.height) / max(1, rect.height))
        let estimatedStepPixels = max(
            1,
            min(
                firstFrame.height - 1,
                Int((CGFloat(abs(configuration.eventScrollDeltaPixels)) * pointToPixelScale).rounded())
            )
        )
        var frames = [
            PositionedFrame(
                image: firstFrame,
                y: 0
            )
        ]
        var previousFrame = firstFrame
        var accumulatedY = 0
        var stopReason = ScrollingCaptureStopReason.reachedEnd

        for _ in 1..<max(1, configuration.maxFrames) {
            if Task.isCancelled {
                stopReason = .cancelled
                break
            }

            guard let nextFrame = await captureFrameAfterEventScroll(
                previousFrame: previousFrame,
                screen: screen,
                rect: rect,
                targetPoint: targetPoint,
                configuration: configuration
            ) else {
                stopReason = .reachedEnd
                break
            }

            accumulatedY += estimatedStepPixels
            frames.append(PositionedFrame(
                image: nextFrame,
                y: accumulatedY
            ))
            previousFrame = nextFrame
        }

        if frames.count >= max(1, configuration.maxFrames) {
            stopReason = .maxFramesReached
        }

        return finish(frames: frames, stopReason: stopReason, configuration: configuration)
    }

    func captureFrameAfterEventScroll(
        previousFrame: CGImage,
        screen: NSScreen,
        rect: CGRect,
        targetPoint: CGPoint,
        configuration: ScrollingCaptureConfiguration
    ) async -> CGImage? {
        for tap in [CGEventTapLocation.cgSessionEventTap, CGEventTapLocation.cghidEventTap] {
            postScrollEvent(.forward, at: targetPoint, configuration: configuration, tap: tap)
            try? await Task.sleep(nanoseconds: configuration.settleDelayNanoseconds)

            guard let nextFrame = await captureFrame(screen: screen, rect: rect),
                  imageDifferenceScore(previousFrame, nextFrame) > 2.0
            else {
                continue
            }

            return nextFrame
        }

        return nil
    }

    func moveToStartingEdge(
        target: ScrollTarget,
        targetPoint: CGPoint,
        initialMetrics: ScrollMetrics,
        canSetScrollValue: Bool,
        configuration: ScrollingCaptureConfiguration
    ) async -> ScrollMetrics? {
        guard let scrollbar = target.scrollbar else { return nil }
        let valueEpsilon = max((initialMetrics.maxValue - initialMetrics.minValue) * 0.0005, 0.0001)

        if canSetScrollValue, setScrollValue(initialMetrics.minValue, on: scrollbar) {
            try? await Task.sleep(nanoseconds: configuration.settleDelayNanoseconds)

            if let metrics = scrollMetrics(for: scrollbar),
               metrics.value <= metrics.minValue + valueEpsilon {
                return metrics
            }
        }

        var metrics = scrollMetrics(for: scrollbar) ?? initialMetrics
        if metrics.value <= metrics.minValue + valueEpsilon {
            return metrics
        }

        let maxAttempts = max(1, configuration.maxActionAttemptsPerFrame * 4)
        for _ in 0..<maxAttempts {
            let previousValue = metrics.value
            guard performScrollAction(.backward, target: target) else {
                break
            }

            try? await Task.sleep(nanoseconds: configuration.actionStepDelayNanoseconds)

            guard let nextMetrics = scrollMetrics(for: scrollbar) else {
                return nil
            }

            metrics = nextMetrics

            if metrics.value <= metrics.minValue + valueEpsilon {
                return metrics
            }

            if abs(metrics.value - previousValue) <= valueEpsilon {
                break
            }
        }

        if let eventMetrics = await moveToStartingEdgeWithEvents(
            target: target,
            targetPoint: targetPoint,
            currentMetrics: metrics,
            valueEpsilon: valueEpsilon,
            configuration: configuration
        ) {
            return eventMetrics
        }

        return metrics.value <= metrics.minValue + valueEpsilon ? metrics : nil
    }

    func moveTowardOffset(
        _ requestedOffsetPoints: CGFloat,
        from currentOffsetPoints: CGFloat,
        layout: ScrollLayout,
        target: ScrollTarget,
        targetPoint: CGPoint,
        canSetScrollValue: Bool,
        configuration: ScrollingCaptureConfiguration
    ) async -> ScrollMetrics? {
        guard let scrollbar = target.scrollbar else { return nil }

        if canSetScrollValue {
            let requestedValue = layout.value(forOffsetPoints: requestedOffsetPoints)
            if setScrollValue(requestedValue, on: scrollbar) {
                try? await Task.sleep(nanoseconds: configuration.settleDelayNanoseconds)

                if let metrics = scrollMetrics(for: scrollbar) {
                    let actualOffsetPoints = layout.offsetPoints(for: metrics.value)
                    if actualOffsetPoints > currentOffsetPoints + layout.minimumMovementPoints {
                        return metrics
                    }
                }
            }
        }

        if let metrics = await moveTowardOffsetWithActions(
            requestedOffsetPoints,
            from: currentOffsetPoints,
            layout: layout,
            target: target,
            configuration: configuration
        ) {
            return metrics
        }

        return await moveTowardOffsetWithEvents(
            requestedOffsetPoints,
            from: currentOffsetPoints,
            layout: layout,
            target: target,
            targetPoint: targetPoint,
            configuration: configuration
        )
    }

    func moveTowardOffsetWithActions(
        _ requestedOffsetPoints: CGFloat,
        from previousOffsetPoints: CGFloat,
        layout: ScrollLayout,
        target: ScrollTarget,
        configuration: ScrollingCaptureConfiguration
    ) async -> ScrollMetrics? {
        guard let scrollbar = target.scrollbar,
              var metrics = scrollMetrics(for: scrollbar)
        else {
            return nil
        }

        var actualOffsetPoints = max(previousOffsetPoints, layout.offsetPoints(for: metrics.value))
        let maxAttempts = max(1, configuration.maxActionAttemptsPerFrame)

        for _ in 0..<maxAttempts {
            guard actualOffsetPoints < requestedOffsetPoints - layout.minimumMovementPoints,
                  metrics.value < metrics.maxValue - layout.valueEpsilon
            else {
                return metrics
            }

            let offsetBeforeAction = actualOffsetPoints
            guard performScrollAction(.forward, target: target) else {
                return metrics.value >= metrics.maxValue - layout.valueEpsilon ? metrics : nil
            }

            try? await Task.sleep(nanoseconds: configuration.actionStepDelayNanoseconds)

            guard let nextMetrics = scrollMetrics(for: scrollbar) else {
                return nil
            }

            metrics = nextMetrics
            actualOffsetPoints = layout.offsetPoints(for: metrics.value)

            if actualOffsetPoints <= offsetBeforeAction + layout.minimumMovementPoints {
                return metrics.value >= metrics.maxValue - layout.valueEpsilon ? metrics : nil
            }
        }

        return actualOffsetPoints > previousOffsetPoints + layout.minimumMovementPoints ? metrics : nil
    }

    func moveToStartingEdgeWithEvents(
        target: ScrollTarget,
        targetPoint: CGPoint,
        currentMetrics: ScrollMetrics,
        valueEpsilon: Double,
        configuration: ScrollingCaptureConfiguration
    ) async -> ScrollMetrics? {
        var metrics = currentMetrics
        if metrics.value <= metrics.minValue + valueEpsilon {
            return metrics
        }

        let maxAttempts = max(1, configuration.maxEventAttemptsPerFrame * 8)
        for _ in 0..<maxAttempts {
            let previousValue = metrics.value
            guard let nextMetrics = await scrollWithEventAndReadMetrics(
                .backward,
                target: target,
                targetPoint: targetPoint,
                previousValue: previousValue,
                valueEpsilon: valueEpsilon,
                configuration: configuration
            ) else {
                return nil
            }

            metrics = nextMetrics

            if metrics.value <= metrics.minValue + valueEpsilon {
                return metrics
            }

            if abs(metrics.value - previousValue) <= valueEpsilon {
                return nil
            }
        }

        return metrics.value <= metrics.minValue + valueEpsilon ? metrics : nil
    }

    func moveTowardOffsetWithEvents(
        _ requestedOffsetPoints: CGFloat,
        from previousOffsetPoints: CGFloat,
        layout: ScrollLayout,
        target: ScrollTarget,
        targetPoint: CGPoint,
        configuration: ScrollingCaptureConfiguration
    ) async -> ScrollMetrics? {
        guard let scrollbar = target.scrollbar,
              var metrics = scrollMetrics(for: scrollbar)
        else {
            return nil
        }

        var actualOffsetPoints = max(previousOffsetPoints, layout.offsetPoints(for: metrics.value))
        let maxAttempts = max(1, configuration.maxEventAttemptsPerFrame)

        for _ in 0..<maxAttempts {
            guard actualOffsetPoints < requestedOffsetPoints - layout.minimumMovementPoints,
                  metrics.value < metrics.maxValue - layout.valueEpsilon
            else {
                return metrics
            }

            let offsetBeforeEvent = actualOffsetPoints
            guard let nextMetrics = await scrollWithEventAndReadMetrics(
                .forward,
                target: target,
                targetPoint: targetPoint,
                previousValue: metrics.value,
                valueEpsilon: layout.valueEpsilon,
                configuration: configuration
            ) else {
                return nil
            }

            metrics = nextMetrics
            actualOffsetPoints = layout.offsetPoints(for: metrics.value)

            if actualOffsetPoints <= offsetBeforeEvent + layout.minimumMovementPoints {
                return metrics.value >= metrics.maxValue - layout.valueEpsilon ? metrics : nil
            }
        }

        return actualOffsetPoints > previousOffsetPoints + layout.minimumMovementPoints ? metrics : nil
    }

    func scrollWithEventAndReadMetrics(
        _ direction: ScrollDirection,
        target: ScrollTarget,
        targetPoint: CGPoint,
        previousValue: Double,
        valueEpsilon: Double,
        configuration: ScrollingCaptureConfiguration
    ) async -> ScrollMetrics? {
        guard let scrollbar = target.scrollbar else { return nil }

        for tap in [CGEventTapLocation.cgSessionEventTap, CGEventTapLocation.cghidEventTap] {
            postScrollEvent(direction, at: targetPoint, configuration: configuration, tap: tap)
            try? await Task.sleep(nanoseconds: configuration.actionStepDelayNanoseconds)

            guard let metrics = scrollMetrics(for: scrollbar) else {
                return nil
            }

            if abs(metrics.value - previousValue) > valueEpsilon {
                return metrics
            }
        }

        return scrollMetrics(for: scrollbar)
    }

    func postScrollEvent(
        _ direction: ScrollDirection,
        at targetPoint: CGPoint,
        configuration: ScrollingCaptureConfiguration,
        tap: CGEventTapLocation
    ) {
        let magnitude = max(1, abs(configuration.eventScrollDeltaPixels))
        let delta: Int32 = direction == .forward ? -magnitude : magnitude
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }

        event.location = targetPoint
        event.post(tap: tap)
    }

    func captureFrame(screen: NSScreen, rect: CGRect) async -> CGImage? {
        await screenshot.takeScreenshot(
            of: screen,
            croppingTo: rect,
            options: ScreenshotCaptureOptions(showsCursor: false)
        )
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
                if let scrollbar = axElementAttribute(element, kAXVerticalScrollBarAttribute as CFString),
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

            if let scrollbar = axElementAttribute(element, kAXVerticalScrollBarAttribute as CFString),
               isVerticalScrollbar(scrollbar) {
                return ScrollTarget(
                    scrollbar: scrollbar,
                    scrollArea: isScrollArea(element) ? element : nearestScrollArea(from: element)
                )
            }

            current = axElementAttribute(element, kAXParentAttribute as CFString)
        }

        return nil
    }

    func nearestScrollArea(from element: AXUIElement) -> AXUIElement? {
        var current = axElementAttribute(element, kAXParentAttribute as CFString)

        for _ in 0..<40 {
            guard let element = current else { break }

            if isScrollArea(element) {
                return element
            }

            current = axElementAttribute(element, kAXParentAttribute as CFString)
        }

        return nil
    }

    func isScrollArea(_ element: AXUIElement) -> Bool {
        stringAttribute(element, kAXRoleAttribute as CFString) == kAXScrollAreaRole as String
    }

    func isVerticalScrollbar(_ element: AXUIElement) -> Bool {
        guard stringAttribute(element, kAXRoleAttribute as CFString) == kAXScrollBarRole as String else {
            return false
        }

        if let orientation = stringAttribute(element, kAXOrientationAttribute as CFString) {
            return orientation == kAXVerticalOrientationValue as String
        }

        guard let size = sizeAttribute(element, kAXSizeAttribute as CFString) else {
            return true
        }

        return size.height >= size.width
    }

    func scrollMetrics(for scrollbar: AXUIElement) -> ScrollMetrics? {
        guard let value = numberAttribute(scrollbar, kAXValueAttribute as CFString),
              let minValue = numberAttribute(scrollbar, kAXMinValueAttribute as CFString),
              let maxValue = numberAttribute(scrollbar, kAXMaxValueAttribute as CFString),
              let geometry = scrollbarGeometry(scrollbar)
        else {
            return nil
        }

        return ScrollMetrics(
            value: value,
            minValue: minValue,
            maxValue: maxValue,
            visibleFraction: geometry.visibleFraction,
            trackHeight: geometry.trackHeight
        )
    }

    func scrollbarGeometry(_ scrollbar: AXUIElement) -> (visibleFraction: Double, trackHeight: CGFloat)? {
        guard let trackSize = sizeAttribute(scrollbar, kAXSizeAttribute as CFString),
              trackSize.height > 0
        else {
            return nil
        }

        let children = childElements(scrollbar)
        let valueIndicator = children.first {
            stringAttribute($0, kAXRoleAttribute as CFString) == kAXValueIndicatorRole as String
        } ?? children
            .compactMap { child -> (element: AXUIElement, size: CGSize)? in
                guard let size = sizeAttribute(child, kAXSizeAttribute as CFString),
                      size.height > 0,
                      size.height <= trackSize.height
                else {
                    return nil
                }

                return (child, size)
            }
            .min { first, second in
                first.size.height < second.size.height
            }?
            .element

        guard let valueIndicator,
              let indicatorSize = sizeAttribute(valueIndicator, kAXSizeAttribute as CFString),
              indicatorSize.height > 0
        else {
            return nil
        }

        let visibleFraction = Double(indicatorSize.height / trackSize.height)
        return (
            visibleFraction: max(0.001, min(1, visibleFraction)),
            trackHeight: trackSize.height
        )
    }

    func childElements(_ element: AXUIElement) -> [AXUIElement] {
        let attributes = [
            kAXVisibleChildrenAttribute as CFString,
            kAXChildrenAttribute as CFString
        ]

        for attribute in attributes {
            if let children = copyAttribute(element, attribute) as? [AXUIElement],
               !children.isEmpty {
                return children
            }
        }

        return []
    }

    func performScrollAction(_ direction: ScrollDirection, target: ScrollTarget) -> Bool {
        if let scrollbar = target.scrollbar,
           performAction(direction.valueAction, on: scrollbar) {
            return true
        }

        if let scrollArea = target.scrollArea,
           performAction(direction.valueAction, on: scrollArea) {
            return true
        }

        guard let scrollbar = target.scrollbar else {
            return false
        }

        for subrole in [direction.pageSubrole, direction.arrowSubrole] {
            if let child = childElements(scrollbar).first(where: {
                stringAttribute($0, kAXSubroleAttribute as CFString) == subrole
            }), performAction(kAXPressAction as CFString, on: child) {
                return true
            }
        }

        return false
    }

    func performAction(_ action: CFString, on element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, action) == .success
    }

    func isAttributeSettable(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return result == .success && settable.boolValue
    }

    func setScrollValue(_ value: Double, on scrollbar: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(
            scrollbar,
            kAXValueAttribute as CFString,
            NSNumber(value: value)
        )

        return result == .success
    }

    func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        return result == .success ? value : nil
    }

    func axElementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return (value as! AXUIElement)
    }

    func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        copyAttribute(element, attribute) as? String
    }

    func numberAttribute(_ element: AXUIElement, _ attribute: CFString) -> Double? {
        guard let value = copyAttribute(element, attribute) else {
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

    func sizeAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        guard let value = copyAttribute(element, attribute),
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

    func activateOwningApplication(for element: AXUIElement) {
        var pid = pid_t()
        let result = AXUIElementGetPid(element, &pid)
        guard result == .success,
              pid != NSRunningApplication.current.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid)
        else {
            return
        }

        app.activate(options: [.activateIgnoringOtherApps])
    }

    func imageDifferenceScore(_ first: CGImage, _ second: CGImage) -> Double {
        guard let firstFingerprint = imageFingerprint(first),
              let secondFingerprint = imageFingerprint(second),
              firstFingerprint.count == secondFingerprint.count,
              !firstFingerprint.isEmpty
        else {
            return 0
        }

        var totalDifference = 0
        for index in firstFingerprint.indices {
            totalDifference += abs(Int(firstFingerprint[index]) - Int(secondFingerprint[index]))
        }

        return Double(totalDifference) / Double(firstFingerprint.count)
    }

    func imageFingerprint(_ image: CGImage) -> [UInt8]? {
        let width = 64
        let height = 64
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: Self.rgbaBitmapInfo
                  )
            else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return rendered ? pixels : nil
    }

    func finish(
        frames: [PositionedFrame],
        stopReason: ScrollingCaptureStopReason,
        configuration: ScrollingCaptureConfiguration
    ) -> ScrollingCaptureResult {
        guard let image = compose(frames: frames, gapTolerance: configuration.gapTolerancePixels) else {
            return .failure(.stitchingFailed)
        }

        switch stopReason {
        case .reachedEnd:
            return .success(image)
        case .maxFramesReached, .cancelled:
            return .partial(image, reason: stopReason)
        }
    }

    func compose(frames: [PositionedFrame], gapTolerance: Int) -> CGImage? {
        guard let firstFrame = frames.first else { return nil }
        guard frames.allSatisfy({ $0.width == firstFrame.width }) else { return nil }

        var pieces: [StitchPiece] = []
        var filledBottom = 0

        for frame in frames.sorted(by: { $0.y < $1.y }) {
            let frameTop = max(0, frame.y)
            let frameBottom = frame.y + frame.height
            guard frameBottom > filledBottom else {
                continue
            }

            if frameTop > filledBottom + gapTolerance {
                return nil
            }

            let pieceTop = max(filledBottom, frameTop)
            let cropY = max(0, pieceTop - frame.y)
            let cropHeight = frameBottom - pieceTop

            guard cropHeight > 0,
                  let croppedImage = frame.image.cropping(to: CGRect(
                    x: 0,
                    y: cropY,
                    width: frame.width,
                    height: cropHeight
                  ))
            else {
                continue
            }

            pieces.append(StitchPiece(
                image: croppedImage,
                visualY: pieceTop,
                height: cropHeight
            ))
            filledBottom = frameBottom
        }

        guard filledBottom > 0,
              let context = CGContext(
                data: nil,
                width: firstFrame.width,
                height: filledBottom,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: Self.rgbaBitmapInfo
              )
        else {
            return nil
        }

        context.interpolationQuality = .none

        for piece in pieces {
            let drawY = filledBottom - piece.visualY - piece.height
            context.draw(piece.image, in: CGRect(
                x: 0,
                y: drawY,
                width: piece.image.width,
                height: piece.height
            ))
        }

        return context.makeImage()
    }

    static var rgbaBitmapInfo: UInt32 {
        CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    }
}
