# Contributing to Cubit

Thanks for your interest in contributing!

## Getting started

1. Clone the repo and open `Cubit.xcodeproj` in Xcode 26 or later (macOS 26 SDK).
2. Build and run the `Cubit` scheme, or from the command line:
   ```sh
   xcodebuild -scheme Cubit -destination 'platform=macOS' build test
   ```
3. Source files under `Sources/Cubit` and `Tests/CubitTests` are picked up automatically
   via Xcode's file-system-synchronized groups — just add files on disk, no project
   editing required.

## Architecture

- **`Sources/Cubit/Core`** — pure, AppKit-free logic: geometry (`CanonicalRect`,
  `CoordinateConverter`), the measurement engine, reference-frame resolution, export layout,
  and the model types. Everything here is fully unit tested and has no dependency on
  `NSEvent`, `NSScreen`, or any other AppKit type. Coordinates enter Core already converted
  into a top-left-origin "canonical" space — Core never touches Cocoa's flipped, per-screen
  coordinate system.
- **`Sources/Cubit/Overlay`** — the AppKit layer: the full-screen overlay window, canvas view,
  HUD, and tool pill. This is where `NSEvent` and `NSScreen` coordinates get converted into
  canonical space exactly once, at the boundary, via `CoordinateConverter`. Everything downstream
  of that conversion works in canonical coordinates.
- **`Sources/Cubit/Capture`** — screen capture via ScreenCaptureKit, plus the Screen Recording
  TCC permission flow (onboarding UI lives in `Sources/Cubit/UI/OnboardingWindow.swift`).
- **`Sources/Cubit/Export`** — turns a frozen capture plus a set of measurements into a
  designed, annotated PNG: layout engine (`Core/Export`), renderer, and the save/copy/drag-out
  exporter.

## Code rules

- **Zero third-party dependencies.** Cubit only links system frameworks (AppKit, ScreenCaptureKit,
  Observation, ServiceManagement, etc.). Don't add a Swift package dependency.
- **SF Symbols only** for UI iconography — no bundled image assets for interface chrome.
- **No file-header comments.** Don't add license/author/date boilerplate at the top of files.
- **Coordinate discipline.** AppKit event and screen coordinates get converted to canonical
  (top-left-origin) space exactly once, at the Overlay boundary, via `CoordinateConverter`.
  `Sources/Cubit/Core` must stay AppKit-free — no `NSEvent`, `NSScreen`, `NSPoint`/`NSRect`
  flipping logic, etc. should ever appear there.

## Tests

- Run the full suite with `xcodebuild -scheme Cubit -destination 'platform=macOS' build test`
  before opening a PR.
- Core logic (geometry, measurement engine, reference resolution, export layout) should be
  unit tested directly — it's pure and fast, there's no excuse to skip it.
- Tests that depend on live system state the CI runner may not have (e.g. an actual Screen
  Recording grant) should `throw XCTSkip(...)` rather than fail when that precondition isn't
  met, and should still fail on genuine regressions.

## Privacy gate

Before committing, make sure your staged diff contains no personally identifying or
machine-specific content: real names, personal email addresses, absolute home-directory
paths (`/Users/...`), hostnames, or Xcode identity settings (`DEVELOPMENT_TEAM`,
`ORGANIZATIONNAME`). A quick self-check, substituting your own identifiers:

```sh
git diff --cached | grep -inE '<your name>|<your email>|/Users/|DEVELOPMENT_TEAM|ORGANIZATIONNAME'
```

That command should produce no output. If it matches something, remove it before committing —
this applies to code, comments, commit messages, and workflow files alike.

## Submitting changes

- Open an issue before starting significant work so it can be discussed first.
- Keep pull requests focused on a single change.
- Use [Conventional Commits](https://www.conventionalcommits.org/) style messages
  (`feat:`, `fix:`, `test:`, `docs:`, etc.).
- Before opening a PR, confirm:
  - [ ] `xcodebuild -scheme Cubit -destination 'platform=macOS' build test` passes
  - [ ] New/changed behavior has test coverage
  - [ ] The privacy-gate grep above is clean on your diff
  - [ ] No third-party dependencies were added
  - [ ] `project.pbxproj` wasn't touched unless the change genuinely requires a build
        setting change (explain why in the PR description if it was)

## Code style

- Follow the conventions already present in the codebase.
- Prefer clarity over cleverness.
