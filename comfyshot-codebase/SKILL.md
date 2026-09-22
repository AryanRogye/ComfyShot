---
name: comfyshot-codebase
description: Use when editing or reviewing the ComfyShot macOS Swift codebase, especially capture flows, window coordination, AppKit integration, and SwiftUI views.
metadata:
  author: Aryan Rogye
  version: "1.0"
---

Guidance for Codex and other coding agents working in this repo.

## What ComfyShot is

ComfyShot is a native macOS screenshot utility focused on fast capture, lightweight editing, and keeping recent screenshots easily accessible.
Screenshots are only stored temporarily. ComfyShot intentionally avoids permanent screenshot storage to keep disk usage low.

## Default Workflow

- Read the relevant Swift files before editing.
- Keep changes tightly scoped to the user's request.
- Do not rewrite unrelated views or refactor broad areas unless explicitly asked.

## Swift Style

- Match the existing file style.
- Use `///` comments above important functions, especially helpers that are not obvious.
- Include small examples in comments when they clarify behavior.
- Prefer comments that are short, practical, and tied to what the code does.
- Avoid noisy comments that simply restate a line of code.
- Keep code ASCII unless the surrounding file already uses non-ASCII for a clear reason.
- Avoid extracting one-off logic into computed properties, variables, or tiny helper functions when the logic is simple and only used once. Keep it inline when doing so makes the code easier to follow.

  For example, avoid:

  ```swift
  private var isReadable: Bool {
      text.count > 10 && !text.isEmpty
  }

  // ...one single usage 100 lines later

  if isReadable {
      ...
  }
  ```

  Rather, keep the condition where it matters if it's simple and only used once:

  ```swift
  if text.count > 10 && !text.isEmpty {
      ...
  }
  ```

- Break up long classes/structs/actors into extensions that make the file easier for humans to scan.

## Organizing large Swift types

Read [references/extensions.md](references/extensions.md) when reorganizing a
large type.

For large classes, structs, and actors:

- Keep stored state, initialization, and the primary public entry points in
  the main declaration.
- Move related behavior into extensions.
- Use clear, human-readable section names that make the file easy to scan.
  Category-style names are encouraged when they make the structure obvious,
  such as `Menubar Actions`, `Delegate Functions`, or `Update Observation`.
- Order sections according to the type's setup and usage flow.
- Avoid extracting trivial one-use logic solely to create another helper.

## Public-Safe Paths

Never hardcode a developer-specific path such as:

```swift
"/Users/aryanrogye/..."
```

