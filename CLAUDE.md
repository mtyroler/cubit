# Cubit — agent instructions

Menu-bar macOS utility: draw rectangles/lines over anything on screen, get live percentages
of a window/screen/custom reference, export designed annotated screenshots. Zero third-party
dependencies. macOS 26+ only.

## Build & test

```sh
xcodebuild -scheme Cubit -destination 'platform=macOS,arch=arm64' build test CODE_SIGNING_ALLOWED=NO
```

CI runs the same on `macos-26` runners (Xcode 26.5 — NEWER local Xcode output, e.g. Icon
Composer files, may not compile there; verify against the CI toolchain when touching assets).
Release: push a `v*` tag → ad-hoc-signed zip via `.github/workflows/release.yml`.

## Architecture

- `Sources/Cubit/Core/` — PURE Swift: no AppKit imports, Sendable, heavily unit-tested.
  Geometry (CanonicalPoint/Rect, CoordinateConverter, MeasurementEngine), Model
  (Measurement, Palette, ReferenceFrame, CursorStyle, MeasurementLabel), Reference
  (resolver + WindowInfoProviding protocol), Export (AnnotationLayoutEngine, ExportLayout),
  Metadata (ExportMetadata).
- `Sources/Cubit/Overlay/` — AppKit overlay: one borderless NSPanel per screen at max window
  level; OverlayCanvasView is flipped (Y-down). **Coordinate discipline: canonical space =
  CG-global (top-left origin, Y-down, points). Mouse events convert to canonical EXACTLY ONCE
  at the top of OverlayCanvasView handlers; everything downstream is canonical-only.**
- `Sources/Cubit/Capture/` — ScreenCaptureKit frozen snapshots + TCC permission flow.
  The live menu bar and Dock always render ABOVE the overlay: never draw frozen content or
  place UI in those regions (top/bottom insets are plumbed per screen — use them).
- `Sources/Cubit/Export/` — render pipeline (crop → layout engine → SwiftUI → PNG, metadata
  stripped at byte level). UserDefaults contract keys documented in ExportLayoutPreferences /
  MetadataPreferences.
- `Sources/Cubit/State/`, `UI/` — @Observable stores, Settings window, onboarding.
- `Tests/CubitTests/` — exact-value assertions for Core; tests needing live system state
  (TCC grants) must `throw XCTSkip` when the precondition is missing, never fail.

## Hard rules

- **Zero third-party dependencies.** Platform frameworks only. Raise exceptions with the
  user before adding anything.
- **SF Symbols for all in-app graphics**; custom artwork only for the app icon.
- **No file-header comments** ("Created by…" leaks identity; use no header at all).
- **Never edit `project.pbxproj`** — file-system-synchronized groups auto-include new files
  under Sources/ and Tests/. Sole exception: a genuinely required build setting, kept minimal.
- **Privacy gate before every commit**: the staged diff must contain no real names, personal
  emails, `/Users/…` paths, hostnames, `DEVELOPMENT_TEAM`, or `ORGANIZATIONNAME`. Do NOT
  write the literal identity strings into any committed file (including this one and
  CONTRIBUTING.md — describing the gate generically is the lesson of a past leak). The
  concrete grep pattern lives in the gitignored `RESUME-v0.3.md`. Git identity is repo-local;
  never touch global git config. Scan binary assets with `strings` before committing.
- Commits: conventional messages. Every overlay capability needs a **visible clickable
  affordance**, not just a key (tool pill pattern). User-approved constants — 15% dim
  default, drag feel — are configurable but defaults stay.

## Process (multi-agent)

- Orchestrator validates independently: build, tests, privacy scan, and **eyes on rendered
  output** for anything visual. Structural verification has missed every real visual bug;
  screenshots find them.
- Spawn a FRESH subagent per new task (self-contained brief); don't accrete context in
  long-lived agents. Concurrent agents editing shared files must use separate git worktrees;
  remove only worktrees you created (exact path), and verify a worktree is properly linked
  (`git worktree list`) before working in it.
- After any commit series, verify HEAD builds on a clean clone if the working tree contains
  another agent's WIP.

For current roadmap, session-resume context, and private constants: `RESUME-v0.3.md`
(gitignored, local machine only).
