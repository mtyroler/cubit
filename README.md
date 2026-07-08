<p align="center">
  <img src="Design/AppIcon/preview.png" width="128" height="128" alt="Cubit app icon">
</p>

<h1 align="center">Cubit</h1>

<p align="center">
  Know exactly how much room your design gives its content. Draw a box, get the percentage.
</p>

<p align="center">
  <a href="https://github.com/mtyroler/cubit/actions/workflows/ci.yml"><img src="https://github.com/mtyroler/cubit/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-blue.svg" alt="macOS 26+">
</p>

<p align="center">
  <img src="Design/ReadmeAssets/export-recipe-app.png" width="100%" alt="A Cubit export over a sample recipe-app window, with three color-coded measurements: a hero photo at 17.4%, recipe details at 22.0%, and breathing room in the sidebar at 14.8%.">
</p>

A cubit was an old unit of length measured forearm-to-fingertip — a measurement you could point at, not just eyeball. That's the idea here too: instead of guessing whether something has enough padding, you draw a box and get the number. The app's icon is a tape measure sticking its tongue out, because measuring things should be a little fun.

## Why

"Does this have enough breathing room?" is a question that usually gets answered by squinting. Cubit turns it into a number: draw a rectangle or a line over anything on screen and it's expressed as a percentage of a window, a display, or a custom reference you define — live, as you draw. Point it at a hero image, a sidebar, a margin, whatever you're trying to get a feel for, and watch the percentage update as you resize. When you've got the measurement that tells the story, export it as an annotated screenshot to drop into a design review, a spec, or a Slack thread.

## Features

- Global hotkey (⌃⌥⌘M by default, rebindable) freezes the screen and opens a full-screen measurement overlay
- Rectangle and horizontal/vertical line tools with a live HUD showing pixels and percent of the reference frame
- Reference frame is the window under your cursor by default; `Tab` cycles to full screen, or draw a custom reference rectangle
- Multiple simultaneous, color-coded measurements with editable labels, selection, nudge/resize, and undo
- Export a designed annotated PNG — callout pills, leader lines, and a legend card — via save, copy, or drag-out
- Window exports crop to the window exactly by default; an "Include surrounding context" toggle in the export menu pads it back out when you want the desktop around it
- Optional metadata footer on exports (machine name, window title, app name) — all off by default
- Menu-bar-first UX (no Dock icon) with a Settings window for shortcuts, appearance, and export defaults
- Zero third-party dependencies

## Install

1. Download the latest `Cubit-vX.Y.Z.zip` from the [Releases](https://github.com/mtyroler/cubit/releases) page and unzip it.
2. Move `Cubit.app` to `/Applications` (or wherever you like).
3. Cubit is ad-hoc signed, not notarized, so Gatekeeper will refuse to open it with a plain double-click. Either:
   - Right-click `Cubit.app` → **Open** → confirm in the dialog that appears (only needed once), or
   - Strip the quarantine flag from Terminal: `xattr -dr com.apple.quarantine /Applications/Cubit.app`
4. On first use, Cubit will ask for **Screen Recording** permission — it's required to freeze the screen for measuring and to capture the image you export. Cubit walks you through the System Settings prompt; nothing is captured until you grant it.

## Usage

Press the hotkey to freeze the screen and open the overlay, then:

| Action | Shortcut |
| --- | --- |
| Open/close measurement overlay | `⌃⌥⌘M` (rebindable in Settings) |
| Rectangle tool | `R` |
| Horizontal line tool | `H` |
| Vertical line tool | `V` |
| Cycle reference frame (window → screen → custom) | `Tab` |
| Draw a custom reference rectangle | `C` |
| Constrain to square / center-out draw | hold `Shift` / `⌥` while dragging |
| Nudge selected measurement | arrow keys (hold `Shift` for 10px steps, `⌥` to resize instead of move) |
| Undo | `⌘Z` |
| Delete selected measurement | `Delete` |
| Open export menu | `⌘E` |
| Save export as PNG | `⌘S` |
| Copy export to clipboard | `⌘C` |
| Close menu / deselect / cancel / dismiss overlay | `Esc` |

<p align="center">
  <img src="Design/ReadmeAssets/export-music-app.png" width="100%" alt="A Cubit export over a sample music-player window, measuring the album art at 9.7%, the playback controls at 6.6%, and breathing room in the sidebar at 13.4%.">
</p>

## Demo

<!-- TODO: replace with a real screen recording of Cubit in action -->

## Privacy

Cubit doesn't talk to the network — nothing you measure, capture, or export leaves your Mac. The optional metadata footer on exports (machine name, window title, app name) is off by default and only ever writes into the image file you choose to save or copy. The two sample exports above were generated against synthetic, throwaway app mockups — no real windows, filenames, or personal content — specifically for this README.

Cubit is unsandboxed. It needs system-wide window and screen information (via `CGWindowList` and system-wide screen capture) to detect the window under your cursor and freeze the whole screen for measuring, which the App Sandbox doesn't permit for third-party apps.

## Building from source

Requires Xcode 26 or later.

```sh
git clone https://github.com/mtyroler/cubit.git
cd cubit
open Cubit.xcodeproj
```

Or from the command line:

```sh
xcodebuild -scheme Cubit -destination 'platform=macOS' build test
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
