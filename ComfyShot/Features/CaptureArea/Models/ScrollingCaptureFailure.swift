//
//  ScrollingCaptureFailure.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 7/1/26.
//

public enum ScrollingCaptureFailure: Error {
    case accessibilityPermissionDenied
    case noElementAtSelectionCenter
    case unsupportedScrollableTarget
    case scrollPositionUnavailable
    case captureFailed
    case stitchingFailed
}
