//
//  ScrollingCaptureModels.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

import CoreImage

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
