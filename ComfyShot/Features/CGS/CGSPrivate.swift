//
//  CGSPrivate.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/9/26.
//

import CoreGraphics

@_silgen_name("_CGSDefaultConnection")
func CGSDefaultConnection() -> CGSConnectionID

@_silgen_name("CGSSetConnectionProperty")
func CGSSetConnectionProperty(
    _ connection: CGSConnectionID,
    _ targetConnection: CGSConnectionID,
    _ key: CFString,
    _ value: CFTypeRef
) -> CGError

/// WindowServer exports this symbol even though the public SDK marks it
/// unavailable. It tells us when another process has made the cursor visible.
@_silgen_name("CGCursorIsVisible")
func CGCursorIsVisible() -> Int32
