# Contributing to Cubit

Thanks for your interest in contributing!

## Getting started

1. Clone the repo and open `Cubit.xcodeproj` in Xcode 26 or later (macOS 26 SDK).
2. Build and run the `Cubit` scheme, or from the command line:
   ```sh
   xcodebuild -scheme Cubit build test
   ```
3. Source files under `Sources/Cubit` and `Tests/CubitTests` are picked up automatically
   via Xcode's file-system-synchronized groups — just add files on disk, no project
   editing required.

## Submitting changes

- Open an issue before starting significant work so it can be discussed first.
- Keep pull requests focused on a single change.
- Make sure `xcodebuild -scheme Cubit build test` passes before opening a PR.

## Code style

- Follow the conventions already present in the codebase.
- Prefer clarity over cleverness.
