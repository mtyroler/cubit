// swift-tools-version: 6.2
import PackageDescription

// The `cubit` command-line tool, for LLM agents and scripts that need Cubit's window
// listing, screen capture, and annotated-export rendering without driving the menu-bar app.
//
// The Xcode app project (Cubit.xcodeproj) is the source of truth for the GUI app and is
// built with `xcodebuild -scheme Cubit …`. This manifest is consumed only by SwiftPM
// (`swift build`/`swift test`) and shares the app's Core + Export code by compiling those
// files directly into the CLI module — no duplicate sources, no `public` sprinkled through
// Core. The Xcode project's file-system-synchronized groups cover `Sources/Cubit` and
// `Tests/CubitTests` only, so `Sources/CubitCLI` / `Tests/CubitCLITests` never leak into the
// app or its test bundle.
//
// The executable TARGET is named `Cubit` (capital C) on purpose: the shared source
// `MeasurementSidecar` refers to the model type as `Cubit.Measurement` to disambiguate it
// from its own nested `Measurement` and from `Foundation.Measurement`, so the module must be
// named `Cubit` for that to resolve. The PRODUCT (and therefore the binary + `swift run`
// name) is the lowercase `cubit`.
let package = Package(
    name: "cubit",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "cubit", targets: ["Cubit"]),
    ],
    targets: [
        .executableTarget(
            name: "Cubit",
            path: "Sources",
            // The app-only layers live under the target path but aren't part of the CLI;
            // excluding them keeps `swift build` free of "unhandled files" warnings.
            exclude: [
                "Cubit/App",
                "Cubit/State",
                "Cubit/UI",
                "Cubit/Overlay",
                "Cubit/Metadata",
                "Cubit/Resources",
                "Cubit/HotkeyManager.swift",
                "Cubit/Capture/FrozenBackgroundLayout.swift",
                "Cubit/Capture/PermissionsManager.swift",
                "Cubit/Export/Exporter.swift",
                "Cubit/Export/ExportLayoutPreferences.swift",
                "Cubit/Export/ExportMenuView.swift",
            ],
            // Core is pure Swift; the listed Export/Capture/Reference files pull in AppKit /
            // SwiftUI / ScreenCaptureKit — all platform frameworks, allowed in the CLI. We do
            // NOT include the app's State/UI/Overlay/App layers.
            sources: [
                "Cubit/Core",
                "Cubit/Reference/CGWindowInfoProvider.swift",
                "Cubit/Capture/ScreenCaptureService.swift",
                "Cubit/Export/ExportRenderer.swift",
                "Cubit/Export/ScreenshotAnnotationView.swift",
                "Cubit/Export/StyledWindowExportView.swift",
                "Cubit/Export/MetadataFooterView.swift",
                "Cubit/Export/ExportTypography.swift",
                "CubitCLI",
            ]
        ),
        .testTarget(
            name: "CubitCLITests",
            dependencies: ["Cubit"],
            path: "Tests/CubitCLITests"
        ),
    ]
)
