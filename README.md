# Cubit

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/mtyroler/cubit/actions/workflows/ci.yml/badge.svg)](https://github.com/mtyroler/cubit/actions/workflows/ci.yml)

Show exactly how much of the screen a design wastes — draw a line or box, get the %, export a marked-up screenshot.

Cubit is a lightweight macOS menu-bar utility for measuring how much of a window or screen a region occupies. Draw a shape over anything on screen and instantly see it expressed as a percentage of a window, a display, or a custom reference frame — then export an annotated screenshot to share.

## Features (planned)

- Global hotkey to draw a measurement overlay anywhere on screen
- Line and box measurement tools with a live heads-up display
- Measure against a window, a full screen, or a custom reference frame
- Multiple simultaneous measurements with labels and a color palette
- Screen capture via ScreenCaptureKit with guided permission onboarding
- Export an annotated screenshot with measurements burned in
- Optional metadata imprints on exports (timestamp, device, display info)
- Menu-bar-first UX with a lightweight settings window

## Requirements

- macOS 14.0 or later

## Build from source

```sh
xcodebuild -scheme Cubit build
```

## Demo

![demo placeholder](docs/demo.gif)

## License

MIT — see [LICENSE](LICENSE).
