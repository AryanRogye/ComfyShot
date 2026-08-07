//
//  FocusablePanel.swift
//  ComfyMark
//
//  Created by Aryan Rogye on 9/12/25.
//

import AppKit

/**
 * Custom NSPanel subclass that can become key and main window.
 * Enables proper focus and interaction handling.
 */
class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    override var canBecomeMain: Bool {
        return true
    }
}

/// Keeps system materials in their active visual state without making the
/// nonactivating dock overlay participate in normal key-window event routing.
final class ActiveAppearancePanel: FocusablePanel {
    @objc(hasKeyAppearance)
    private func activePublicKeyAppearance() -> Bool {
        true
    }
    
    @objc(_hasKeyAppearance)
    private func activeKeyAppearance() -> Bool {
        true
    }
    
    @objc(_hasActiveAppearance)
    private func activeAppearance() -> Bool {
        true
    }
    
    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    private func activeAppearanceIgnoringKeyFocus() -> Bool {
        true
    }
}
