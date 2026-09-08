//
//  ShiftClickCapturable.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/8/26.
//

import SwiftUI

struct ShiftClickCapturable: NSViewRepresentable {

    var didShiftClick: () -> Void

    func makeNSView(context: Context) -> ShiftClickCapturableView {
        let v = ShiftClickCapturableView(didShiftClick: didShiftClick)
        return v
    }
    func updateNSView(_ nsView: ShiftClickCapturableView, context: Context) {

    }
}

final class ShiftClickCapturableView: NSView {

    var flagsMonitor: Any?
    var didShiftClick: () -> Void

    init(didShiftClick: @escaping () -> Void) {
        self.didShiftClick = didShiftClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init?(coder: NSCoder) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }

            let point = self.convert(event.locationInWindow, from: nil)

            if self.bounds.contains(point),
               event.modifierFlags.contains(.shift) {
                didShiftClick()
            }

            return event
        }
    }

    deinit {
        // Guarantee clean up when the view is destroyed
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
