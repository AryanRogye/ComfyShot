# CaptureArea/Input

This folder handles input while the capture overlay is open. The three files
split responsibility between receiving system events, applying capture
behavior, and changing the cursor.

```text
CaptureArea/Input/
|
+-- CaptureInputInterceptor.swift
|   macOS event tap: subscribes to mouse + keyboard events, then consumes
|   them so the app under the capture overlay does not react.
|
+-- ComfyShotInputBridge.swift
|   Capture behavior: maps intercepted events to overlay/model actions;
|   chooses draw, move, or resize; converts screen points to overlay points;
|   updates the cursor during hover and drag.
|
+-- SystemCursorController.swift
    Cursor adapter: maps a requested shape to NSCursor and applies/clears
    the intercepted cursor override.
```

## Event and action flow

```text
CaptureAreaCoordinator.show()
        |
        | supplies one OverlayContext (screen + panel + model) per display
        v
ComfyShotInputBridge.start(contexts, cancel, clearSelection)
        |
        +---- CaptureInputInterceptor.start(callbacks)
        |          |
        |          +-- installs a session CGEvent tap on the main run loop
        |          +-- mouse down / drag / up --> bridge callbacks
        |          +-- Enter --> capture selected rect
        |          +-- Escape --> cancel
        |          +-- Shift --> toggle resize-grid behavior
        |          +-- Delete --> clear selection
        |          +-- scroll / secondary buttons / other keys --> consumed
        |
        +---- on success: disable panel cursor rects and start hover timer
        |     on failure: coordinator can use regular AppKit panel input
        v
ComfyShotInputBridge
        |
        +-- hit-test global pointer against OverlayContext.panel
        +-- convert global screen coordinates to local overlay coordinates
        +-- choose a drag operation once, at mouse down:
        |      no selection / click outside --> draw
        |      click within selection       --> move
        |      click near an edge/handle    --> resize
        |      Shift + selection            --> 3x3 grid: center moves,
        |                                      outer cells resize
        +-- call that context.model to update/end draw, move, or resize
        +-- request crosshair, hand, or resize cursor
                   |
                   v
        SystemCursorController
                   |
                   +-- applies CaptureCursorOverride cursor
                   +-- clears override when the input session stops
```

## Session end

```text
Escape / capture / coordinator hide
        -> ComfyShotInputBridge.stop()
        -> stop timer and event tap
        -> clear cursor override
        -> re-enable any panel cursor rects disabled at start
        -> clear overlay, drag, and modifier state
```

## Where the neighboring pieces live

```text
../CaptureAreaCoordinator.swift  creates overlays; starts/stops this bridge;
                                 receives capture and cancel outcomes
../Models/OverlayContext.swift   groups a display, its panel, and its model
../Models/CaptureAreaModel.swift owns selection geometry and capture callback
../Views/SelectionRect.swift     draws selection and defines UI cursor behavior
```

The key distinction: `CaptureInputInterceptor` knows about Core Graphics
events; `ComfyShotInputBridge` knows what those events mean for capture.
