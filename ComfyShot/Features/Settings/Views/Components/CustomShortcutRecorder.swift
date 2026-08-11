//
//  CustomShortcutRecorder.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 8/10/26.
//

import SwiftUI
import AppKit
import Observation
import KeyboardShortcuts
import Carbon.HIToolbox

struct CustomShortcutRecorder: View {
    let action: ShortcutAction
    @State private var recorder: ShortcutRecorderModel

    init(action: ShortcutAction) {
        self.action = action
        _recorder = State(initialValue: ShortcutRecorderModel(action: action))
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: recorder.clearShortcut) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!recorder.hasShortcut)
            .opacity(recorder.hasShortcut ? 1 : 0)
            .help("Clear \(action.label) shortcut")
            .accessibilityLabel("Clear \(action.label) shortcut")

            Button(action: recorder.toggleRecording) {
                Text(recorder.displayedTitle)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(recorder.titleColor)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Click, then press a keyboard shortcut")
            .accessibilityLabel("\(action.label) shortcut")
            .accessibilityValue(recorder.accessibilityValue)
        }
        .onDisappear { recorder.cancelRecording() }
    }
}

@Observable
@MainActor
final class ShortcutRecorderModel {
    private enum RecordingResult {
        case shortcut(KeyboardShortcuts.Shortcut)
        case clear
        case cancel
        case invalid(String)
    }
    
    private static weak var activeRecorder: ShortcutRecorderModel?
    static let shortcutDidChange = Notification.Name("ComfyShotShortcutDidChange")
    
    let actionType: ShortcutAction
    private(set) var displayedTitle: String
    private(set) var titleColor: Color = .primary
    private(set) var accessibilityValue: String
    var hasShortcut: Bool { actionType.shortcutName.shortcut != nil }
    
    private var eventMonitor: Any?
    private var pendingShortcut: KeyboardShortcuts.Shortcut?
    private var wasKeyboardShortcutsEnabled = true
    private var isRecording = false
    private var windowResignObserver: NSObjectProtocol?
    private var errorTask: Task<Void, Never>?
    
    init(action: ShortcutAction) {
        self.actionType = action
        let title = action.shortcutName.shortcut?.description ?? "Record Shortcut"
        self.displayedTitle = title
        self.accessibilityValue = title
    }
    
    isolated deinit {
        errorTask?.cancel()
        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
        }
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
    
    private func refreshDisplayedShortcut() {
        guard !isRecording else { return }
        
        displayedTitle = actionType.shortcutName.shortcut?.description ?? "Record Shortcut"
        titleColor = .primary
        accessibilityValue = displayedTitle
    }

    func clearShortcut() {
        if isRecording {
            finishRecording(with: .clear)
            return
        }

        actionType.shortcutName.shortcut = nil
        refreshDisplayedShortcut()
        NotificationCenter.default.post(name: Self.shortcutDidChange, object: self)
    }
    
    func toggleRecording() {
        if isRecording {
            finishRecording(with: .cancel)
            return
        }
        
        Self.activeRecorder?.finishRecording(with: .cancel)
        Self.activeRecorder = self
        
        isRecording = true
        pendingShortcut = nil
        wasKeyboardShortcutsEnabled = KeyboardShortcuts.isEnabled
        KeyboardShortcuts.isEnabled = false
        
        displayedTitle = "Press Shortcut"
        titleColor = .accentColor
        accessibilityValue = "Recording. Press a shortcut, Escape to cancel, or Delete to clear."

        if let window = NSApp.keyWindow {
            windowResignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishRecording(with: .cancel) }
            }
        }
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func cancelRecording() {
        finishRecording(with: .cancel)
    }
    
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        
        guard event.type == .keyDown || event.type == .keyUp else { return event }
        
        if event.type == .keyDown {
            guard !event.isARepeat else { return nil }
            
            switch Int(event.keyCode) {
            case kVK_Escape:
                finishRecording(with: .cancel)
                return nil
            case kVK_Delete, kVK_ForwardDelete:
                if event.modifierFlags.shortcutModifiers.isEmpty {
                    finishRecording(with: .clear)
                    return nil
                }
            case kVK_Tab:
                if event.modifierFlags.shortcutModifiers.isEmpty {
                    finishRecording(with: .cancel)
                    return nil
                }
            default:
                break
            }
            
            guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
                finishRecording(with: .invalid("Unsupported Shortcut"))
                return nil
            }
            
            guard shortcut.hasRequiredModifier else {
                finishRecording(with: .invalid("Add ⌘, ⌥, or ⌃"))
                return nil
            }
            
            pendingShortcut = shortcut
            displayedTitle = shortcut.description
            accessibilityValue = "\(shortcut.description), release to save"
            return nil
        }
        
        guard
            let pendingShortcut,
            pendingShortcut.carbonKeyCode == Int(event.keyCode)
        else {
            return nil
        }
        
        finishRecording(with: validationResult(for: pendingShortcut))
        return nil
    }
    
    private func validationResult(
        for shortcut: KeyboardShortcuts.Shortcut
    ) -> RecordingResult {
        if let duplicate = ShortcutAction.allCases.first(where: {
            $0 != actionType && $0.shortcutName.shortcut == shortcut
        }) {
            return .invalid("Used by \(duplicate.label)")
        }
        
        if shortcut.isTakenBySystem {
            return .invalid("Used by macOS")
        }
        
        if let menuItem = shortcut.conflictingMainMenuItem {
            return .invalid("Used by \(menuItem.title)")
        }
        
        return .shortcut(shortcut)
    }
    
    private func finishRecording(with result: RecordingResult) {
        guard isRecording else { return }
        
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
            self.windowResignObserver = nil
        }
        
        isRecording = false
        pendingShortcut = nil
        KeyboardShortcuts.isEnabled = wasKeyboardShortcutsEnabled
        
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }
        
        switch result {
        case .shortcut(let shortcut):
            actionType.shortcutName.shortcut = shortcut
            refreshDisplayedShortcut()
            NotificationCenter.default.post(name: Self.shortcutDidChange, object: self)
        case .clear:
            actionType.shortcutName.shortcut = nil
            refreshDisplayedShortcut()
            NotificationCenter.default.post(name: Self.shortcutDidChange, object: self)
        case .cancel:
            refreshDisplayedShortcut()
        case .invalid(let message):
            NSSound.beep()
            displayedTitle = message
            titleColor = .red
            accessibilityValue = message
            
            errorTask?.cancel()
            errorTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self?.refreshDisplayedShortcut()
            }
        }
    }
}

private extension NSEvent.ModifierFlags {
    var shortcutModifiers: Self {
        intersection([.command, .option, .control, .shift, .function])
    }
}

private extension KeyboardShortcuts.Shortcut {
    var hasRequiredModifier: Bool {
        let modifiers = modifiers.shortcutModifiers
        if !modifiers.intersection([.command, .option, .control]).isEmpty {
            return true
        }
        
        return (kVK_F1...kVK_F20).contains(carbonKeyCode)
    }
    
    @MainActor
    var conflictingMainMenuItem: NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        return matchingItem(in: mainMenu)
    }
    
    @MainActor
    private func matchingItem(in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            var keyEquivalent = item.keyEquivalent
            var menuModifiers = item.keyEquivalentModifierMask.shortcutModifiers
            
            if modifiers.contains(.shift), keyEquivalent.lowercased() != keyEquivalent {
                keyEquivalent = keyEquivalent.lowercased()
                menuModifiers.insert(.shift)
            }
            
            if
                nsMenuItemKeyEquivalent == keyEquivalent,
                modifiers.shortcutModifiers == menuModifiers
            {
                return item
            }
            
            if let submenu = item.submenu, let match = matchingItem(in: submenu) {
                return match
            }
        }
        
        return nil
    }
}
