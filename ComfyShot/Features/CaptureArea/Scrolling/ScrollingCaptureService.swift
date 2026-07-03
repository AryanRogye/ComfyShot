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

@MainActor
/// Captures a selected region repeatedly while driving the underlying scrollable content.
public final class ScrollingCaptureService {
    private let screenshot: any ScreenshotProviding
    private let discoverer: ScrollingCaptureDiscoverer

    /// Creates a scrolling capture service with screenshot capture and scroll target discovery dependencies.
    public init(
        screenshot: any ScreenshotProviding,
        discoverer: ScrollingCaptureDiscoverer? = nil
    ) {
        self.screenshot = screenshot
        self.discoverer = discoverer ?? ScrollingCaptureDiscoverer()
    }

    /// Captures a stitched image for `rect` by discovering the scrollable content at `targetPoint`.
    public func capture(
        screen: NSScreen,
        rect: CGRect,
        targetPoint: CGPoint,
        configuration: ScrollingCaptureConfiguration = .default
    ) async -> ScrollingCaptureResult {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityPermissionDenied)
        }

        guard let discovery = discoverer.discover(
            preferredTargetPoint: targetPoint,
            screen: screen,
            rect: rect
        ) else {
            return .failure(.noElementAtSelectionCenter)
        }

        discovery.hitElement.activateOwningApplication()

        guard let scrollbar = discovery.target.scrollbar else {
            return await captureWithEventsOnly(
                screen: screen,
                rect: rect,
                targetPoint: discovery.point,
                configuration: configuration
            )
        }

        let canSetScrollValue = scrollbar.isAttributeSettable(kAXValueAttribute as CFString)
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
            ScrollingCaptureFrame(
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

            frames.append(ScrollingCaptureFrame(
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
    /// Direction abstraction for AX actions and synthetic wheel event deltas.
    enum ScrollDirection {
        case backward
        case forward

        /// AX action used when directly incrementing or decrementing a scroll element.
        var valueAction: CFString {
            switch self {
            case .backward:
                return kAXDecrementAction as CFString
            case .forward:
                return kAXIncrementAction as CFString
            }
        }

        /// Scrollbar page button subrole for this direction.
        var pageSubrole: String {
            switch self {
            case .backward:
                return kAXDecrementPageSubrole as String
            case .forward:
                return kAXIncrementPageSubrole as String
            }
        }

        /// Scrollbar arrow button subrole for this direction.
        var arrowSubrole: String {
            switch self {
            case .backward:
                return kAXDecrementArrowSubrole as String
            case .forward:
                return kAXIncrementArrowSubrole as String
            }
        }
    }

    /// AX scrollbar state plus geometry needed to map AX values to capture offsets.
    struct ScrollMetrics {
        let value: Double
        let minValue: Double
        let maxValue: Double
        let visibleFraction: Double
        let trackHeight: CGFloat

        /// Whether the scrollbar exposes enough information to build a scroll layout.
        var hasUsableScrollRange: Bool {
            maxValue > minValue && visibleFraction > 0 && visibleFraction <= 1 && trackHeight > 0
        }
    }

    /// Converts between scrollbar values, screen points, and output image pixels.
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

        /// Whether the layout can produce meaningful movement and stitch offsets.
        var isUsable: Bool {
            valueRange > 0 && maximumOffsetPoints >= 0 && pointToPixelScale > 0
        }

        /// Small tolerance for AX scroll value comparisons.
        var valueEpsilon: Double {
            max(valueRange * 0.0005, 0.0001)
        }

        /// Minimum point movement worth treating as a new frame position.
        var minimumMovementPoints: CGFloat {
            max(0.5, 1 / pointToPixelScale)
        }

        /// Maps an AX scrollbar value to content offset in points.
        func offsetPoints(for value: Double) -> CGFloat {
            let normalized = (value - minValue) / valueRange
            return CGFloat(max(0, min(1, normalized))) * maximumOffsetPoints
        }

        /// Maps a content offset in points back to an AX scrollbar value.
        func value(forOffsetPoints offset: CGFloat) -> Double {
            guard maximumOffsetPoints > 0 else { return minValue }

            let normalized = Double(max(0, min(maximumOffsetPoints, offset)) / maximumOffsetPoints)
            return minValue + normalized * valueRange
        }

        /// Converts a point offset into pixel space for stitched output placement.
        func pixelOffset(forOffsetPoints offset: CGFloat) -> Int {
            max(0, Int((offset * pointToPixelScale).rounded()))
        }
    }

    /// Captures by posting wheel events only when AX discovery finds a scroll area without a scrollbar.
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
            ScrollingCaptureFrame(
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
            frames.append(ScrollingCaptureFrame(
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

    /// Posts wheel events and returns the next frame only if image content visibly changes.
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
                  ScrollingCaptureStitcher.imageDifferenceScore(previousFrame, nextFrame) > 2.0
            else {
                continue
            }

            return nextFrame
        }

        return nil
    }

    /// Moves the scroll target to its starting edge before frame collection begins.
    func moveToStartingEdge(
        target: ScrollTarget,
        targetPoint: CGPoint,
        initialMetrics: ScrollMetrics,
        canSetScrollValue: Bool,
        configuration: ScrollingCaptureConfiguration
    ) async -> ScrollMetrics? {
        guard let scrollbar = target.scrollbar else { return nil }
        let valueEpsilon = max((initialMetrics.maxValue - initialMetrics.minValue) * 0.0005, 0.0001)

        if canSetScrollValue, scrollbar.setNumberAttribute(initialMetrics.minValue, kAXValueAttribute as CFString) {
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

    /// Moves toward the requested content offset using the most reliable available mechanism.
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
            if scrollbar.setNumberAttribute(requestedValue, kAXValueAttribute as CFString) {
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

    /// Attempts forward movement through AX actions on the scrollbar, scroll area, or scrollbar children.
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

    /// Uses synthetic wheel events to move back to the beginning when direct AX movement stalls.
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

    /// Attempts forward movement through synthetic wheel events and validates it via AX metrics.
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

    /// Posts one wheel event and returns updated metrics when the AX value changes.
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

    /// Posts a pixel-based scroll wheel event at the selected target point.
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

    /// Captures the selected region without the pointer for a single stitched frame.
    func captureFrame(screen: NSScreen, rect: CGRect) async -> CGImage? {
        await screenshot.takeScreenshot(
            of: screen,
            croppingTo: rect,
            options: ScreenshotCaptureOptions(showsCursor: false)
        )
    }

    /// Reads the current AX scrollbar value range and thumb geometry.
    func scrollMetrics(for scrollbar: AXUIElement) -> ScrollMetrics? {
        guard let value = scrollbar.numberAttribute(kAXValueAttribute as CFString),
              let minValue = scrollbar.numberAttribute(kAXMinValueAttribute as CFString),
              let maxValue = scrollbar.numberAttribute(kAXMaxValueAttribute as CFString),
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

    /// Estimates visible content fraction and track height from the scrollbar thumb.
    func scrollbarGeometry(_ scrollbar: AXUIElement) -> (visibleFraction: Double, trackHeight: CGFloat)? {
        guard let trackSize = scrollbar.sizeAttribute(kAXSizeAttribute as CFString),
              trackSize.height > 0
        else {
            return nil
        }

        let children = scrollbar.childElements()
        let valueIndicator = children.first {
            $0.stringAttribute(kAXRoleAttribute as CFString) == kAXValueIndicatorRole as String
        } ?? children
            .compactMap { child -> (element: AXUIElement, size: CGSize)? in
                guard let size = child.sizeAttribute(kAXSizeAttribute as CFString),
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
              let indicatorSize = valueIndicator.sizeAttribute(kAXSizeAttribute as CFString),
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

    /// Performs the best matching AX scroll action for the requested direction.
    func performScrollAction(_ direction: ScrollDirection, target: ScrollTarget) -> Bool {
        if let scrollbar = target.scrollbar,
           scrollbar.performAction(direction.valueAction) {
            return true
        }

        if let scrollArea = target.scrollArea,
           scrollArea.performAction(direction.valueAction) {
            return true
        }

        guard let scrollbar = target.scrollbar else {
            return false
        }

        for subrole in [direction.pageSubrole, direction.arrowSubrole] {
            if let child = scrollbar.childElements().first(where: {
                $0.stringAttribute(kAXSubroleAttribute as CFString) == subrole
            }), child.performAction(kAXPressAction as CFString) {
                return true
            }
        }

        return false
    }

    /// Converts captured frames into a success or partial result after stitching.
    func finish(
        frames: [ScrollingCaptureFrame],
        stopReason: ScrollingCaptureStopReason,
        configuration: ScrollingCaptureConfiguration
    ) -> ScrollingCaptureResult {
        guard let image = ScrollingCaptureStitcher.compose(
            frames: frames,
            gapTolerance: configuration.gapTolerancePixels
        ) else {
            return .failure(.stitchingFailed)
        }

        switch stopReason {
        case .reachedEnd:
            return .success(image)
        case .maxFramesReached, .cancelled:
            return .partial(image, reason: stopReason)
        }
    }
}
