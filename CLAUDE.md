# Cubit — agent instructions

Menu-bar macOS utility: draw rectangles/lines over anything on screen, get live percentages
of a window/screen/custom reference, export designed annotated screenshots. Since v0.3 the same
engine is also agent-facing: a JSON sidecar, a `cubit` CLI, a `cubit-mcp` MCP server, and a
live-overlay handoff that puts agent-proposed measurements on the user's real screen as editable
shapes. Zero third-party dependencies. macOS 26+ only.

## Build & test

The repo holds TWO build systems over overlapping sources. Touch either surface → run both.

```sh
# The GUI app (Xcode project; source of truth for the app target).
xcodebuild -scheme Cubit -destination 'platform=macOS,arch=arm64' build test CODE_SIGNING_ALLOWED=NO
# The agent binaries (SwiftPM): .build/{debug,release}/cubit and cubit-mcp.
swift build && swift test
```

CI runs both on `macos-26` runners (Xcode 26.5 — NEWER local Xcode output, e.g. Icon Composer
files, may not compile there; verify against the CI toolchain when touching assets).
Release: push a `v*` tag → `.github/workflows/release.yml` publishes TWO ad-hoc-signed zips,
`Cubit-<tag>.zip` (the app) and `cubit-tools-<tag>.zip` (universal `cubit` + `cubit-mcp`). The
SwiftPM bin directory moved between toolchains, so the workflow asks for it via
`swift build --show-bin-path` rather than hardcoding — keep it that way.

## Architecture

- `Sources/Cubit/Core/` — PURE Swift: no AppKit imports, Sendable, heavily unit-tested.
  Geometry (CanonicalPoint/Rect, CoordinateConverter, MeasurementEngine), Model
  (Measurement, Palette, ReferenceFrame, CursorStyle, MeasurementLabel), Reference
  (resolver + WindowInfoProviding protocol), Export (AnnotationLayoutEngine, ExportLayout),
  Metadata (ExportMetadata), Sidecar (MeasurementSidecar), Handoff (HandoffDocument,
  HandoffURL, HandoffMapper).
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

### Agent surfaces (v0.3)

- `Sources/CubitCLI/` — the `cubit` command: `windows`, `capture`, `annotate`, `show`.
  Machine JSON → stdout; human/error text → stderr. Exit codes are a CONTRACT agents branch
  on (0 ok, 1 generic, 2 usage, 3 permission denied, 4 not found/ambiguous) — see `Help.swift`,
  which is the user-facing schema doc for `regions.json` and the handoff document.
- `Sources/CubitMCP/` — the `cubit-mcp` stdio JSON-RPC server (hand-rolled; the zero-dep rule
  applies to MCP too). Tools: `list_windows`, `measure_region`, `annotate_screenshot`,
  `show_overlay`, `analyze_dead_space`. `Security.swift` holds `PathSandbox` (`--root`) and the
  input size caps. Tool errors are tagged (`permission_denied:`/`not_found:`/`forbidden:`/
  `too_large:`/`invalid_arguments:`) — keep the tags stable.
- `Executables/cubit`, `Executables/cubit-mcp` — thin `@main` shims only. Both boot an
  `.accessory` NSApplication (ImageRenderer/ScreenCaptureKit need a live run loop).
- `Package.swift` — ONE internal library target (`Cubit`, capital C, required by
  `MeasurementSidecar`'s `Cubit.Measurement` reference) shared by both binaries, so the CLI and
  MCP server cannot drift. Adding a file under `Sources/Cubit/` that the binaries shouldn't
  compile means adding it to the target's `exclude` list.
- `Tests/CubitCLITests/`, `Tests/CubitMCPTests/` — SwiftPM-only; invisible to the app target.

**Two coordinate spaces, deliberately distinct.** `cubit windows`, `measure_region`,
`analyze_dead_space`, and the HANDOFF document are CANONICAL POINTS (top-left, y-down) so an
agent pipes a window frame straight into a proposal. `annotate` / `annotate_screenshot`
`regions.json` is IMAGE PIXELS. Never unify these types.

## Hard rules

- **Zero third-party dependencies.** Platform frameworks only. Raise exceptions with the
  user before adding anything.
- **SF Symbols for all in-app graphics**; custom artwork only for the app icon.
- **No file-header comments** ("Created by…" leaks identity; use no header at all).
- **Never edit `project.pbxproj`** — file-system-synchronized groups auto-include new files
  under Sources/ and Tests/. Sole exception: a genuinely required build setting, kept minimal.
  The synchronized groups cover `Sources/Cubit` and `Tests/CubitTests` ONLY; that is why the
  agent-surface code lives in `Sources/CubitCLI`, `Sources/CubitMCP`, and `Executables/`.
- **Agent input is untrusted.** Every agent-supplied path goes through `PathSandbox` before any
  read or write; size-cap before allocating or decoding. The `cubit://` URL handler is an
  EXTERNAL attack surface (any app or webpage can open one): it stays strictly read-only and
  non-destructive — parse, draw dismissible editable shapes, never write/capture/export/execute.
  A malformed or oversized payload is a silent, logged no-op, never a crash.
- **`cubit-mcp` stdout is JSON-RPC only.** fd 1 is redirected to stderr before NSApplication
  starts; protocol frames go to the saved real stdout. Never `print()` from library code on the
  MCP path — use `mcpLog` (stderr). The same discipline in the CLI: JSON to stdout, prose to
  stderr.
- **One implementation, three surfaces.** App export, `cubit annotate`, and
  `annotate_screenshot` must stay pixel-identical: change the shared renderer/layout engine, not
  a copy. A new capability belongs in the shared library, then gets exposed by each surface.
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

- Orchestrator validates independently: build (both build systems), tests, privacy scan, and
  **eyes on rendered output** for anything visual. Structural verification has missed every real
  visual bug; screenshots find them.
- Agent surfaces get **run**, not just compiled: `cubit windows | head`, a real `annotate` whose
  PNG you look at, and for MCP a hand-fed JSON-RPC line on stdin. A tool whose schema typechecks
  can still return nonsense.
- Spawn a FRESH subagent per new task (self-contained brief); don't accrete context in
  long-lived agents. Concurrent agents editing shared files must use separate git worktrees;
  remove only worktrees you created (exact path), and verify a worktree is properly linked
  (`git worktree list`) before working in it.
- After any commit series, verify HEAD builds on a clean clone if the working tree contains
  another agent's WIP.

For current roadmap, session-resume context, and private constants: `RESUME-v0.3.md`
(gitignored, local machine only).
