<p align="center">
  <img width="960" alt="ComfyShot" src="https://github.com/user-attachments/assets/dbe25b19-b83c-48a6-a33d-09130d3c3845" />
</p>

<p align="center">
  A comfortable, native screenshot tool for macOS.
</p>

<p align="center">
  <a href="https://github.com/AryanRogye/ComfyShot/releases/latest">Download</a>
  ·
  <a href="https://github.com/AryanRogye/ComfyShot/issues/new">Report a bug</a>
</p>

## About

ComfyShot lives in your menu bar and keeps screen capture close at hand. Capture a display, select a region, or stitch together scrolling content. Each result appears in a lightweight stack on the display where it was captured, ready to open, drag into another app, edit, or dismiss.

## Features

- Full-screen capture on the display under your pointer
- Resizable area capture with live dimensions
- Scrolling capture for content that extends beyond the viewport
- Per-display screenshot stacks with an overflow gallery
- Drag-and-drop PNGs directly into other apps
- Built-in image editor with drawing tools, undo, redo, and PNG export
- Customizable global keyboard shortcuts
- Configurable selection overlay and editor defaults
- Automatic updates through Sparkle

## Requirements

- macOS 26 or later
- Accessibility permission
- Screen Recording permission

ComfyShot asks for both permissions during its first launch. macOS may require the app to be restarted after Screen Recording access is granted.

## Installation

1. Download the latest DMG from [GitHub Releases](https://github.com/AryanRogye/ComfyShot/releases/latest).
2. Open the DMG and move ComfyShot to your Applications folder.
3. Launch ComfyShot and grant the requested Accessibility and Screen Recording permissions.
4. Look for the ComfyShot icon in the menu bar.

## Usage

Choose a capture mode from the menu-bar icon or use one of the default shortcuts:

| Action | Default shortcut |
| --- | --- |
| Capture Screen | <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>1</kbd> |
| Capture Area | <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>2</kbd> |
| Scrolling Capture | <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>`</kbd> |

Shortcuts can be changed under **ComfyShot → Settings → Shortcuts**.

After taking a screenshot, hover over it to reveal its controls. You can open it as a PNG, drag it into another app, edit it, or remove it from the stack.

## Building from source

You will need Xcode 26 or later.

```sh
git clone https://github.com/AryanRogye/ComfyShot.git
cd ComfyShot
open ComfyShot.xcodeproj
```

Select the **ComfyShot** scheme in Xcode and run the project. Swift Package Manager will resolve the dependencies automatically.

You can also build from the command line:

```sh
xcodebuild -project ComfyShot.xcodeproj \
  -scheme ComfyShot \
  -configuration Debug \
  build
```

The project uses:

- [SwiftUI](https://developer.apple.com/xcode/swiftui/) and AppKit
- [SnapCore](https://github.com/AryanRogye/SnapCore) for screen capture
- [DrawKit](https://github.com/AryanRogye/DrawKit) for image annotation
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for global shortcuts
- [Defaults](https://github.com/sindresorhus/Defaults) for preferences
- [Sparkle](https://github.com/sparkle-project/Sparkle) for updates

## Contributing

Bug reports, ideas, and pull requests are welcome. If you find a problem, [open an issue](https://github.com/AryanRogye/ComfyShot/issues) with the macOS version, steps to reproduce it, and any relevant screenshots or logs.
