// swift-tools-version: 6.2
import PackageDescription

// Two agent-facing binaries share one implementation:
//
//   • `cubit`     — the command-line tool (window listing, capture, annotated export).
//   • `cubit-mcp` — a Model Context Protocol server that exposes the same capabilities to
//                   LLM agents over stdio JSON-RPC.
//
// Both wrap the SAME window-enumeration, geometry, and export code. SwiftPM refuses to let two
// targets compile overlapping source files, so the "share a `sources` array between two
// executables" shape is impossible. Instead the shared implementation — the app's pure `Core`,
// the select Export/Capture/Reference files, the CLI command logic, and the MCP tool/protocol
// logic — all live in ONE internal library target, `Cubit`, and each binary is a razor-thin
// `@main` shim that depends on it. That keeps everything internal within the package (only the
// two entry points, `CubitCLI` and `MCPServer`, plus `ExitCode`, are `public`) and guarantees
// the CLI and the MCP server can never drift, because there is a single copy of the code.
//
// The Xcode app project (Cubit.xcodeproj) remains the source of truth for the GUI app; its
// file-system-synchronized groups cover `Sources/Cubit` and `Tests/CubitTests` only, so
// `Sources/CubitCLI`, `Sources/CubitMCP`, and their test bundles never leak into the app target.
//
// The library TARGET is named `Cubit` (capital C) on purpose: the shared source
// `MeasurementSidecar` refers to the model type as `Cubit.Measurement` to disambiguate it from
// its own nested `Measurement` and from `Foundation.Measurement`, so the module must be named
// `Cubit`. The PRODUCTS (binary names) are the lowercase `cubit` and `cubit-mcp`.
let package = Package(
    name: "cubit",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "cubit", targets: ["CubitCLIExe"]),
        .executable(name: "cubit-mcp", targets: ["CubitMCP"]),
    ],
    targets: [
        // The shared implementation. Compiles the app's Core (pure Swift) plus the
        // Export/Capture/Reference files that pull in platform frameworks (AppKit / SwiftUI /
        // ScreenCaptureKit — all allowed), plus the CLI command logic (`Sources/CubitCLI`) and
        // the MCP tool/protocol logic (`Sources/CubitMCP`). The two `@main` shims live under
        // `Executables/` so their target paths don't nest inside this one.
        .target(
            name: "Cubit",
            path: "Sources",
            exclude: [
                // App-only layers: not part of either binary.
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
                "CubitMCP",
            ]
        ),
        // `cubit` — the CLI. One file: the `@main` that boots an `.accessory` NSApplication and
        // hands off to the library's `CubitCLI.run`.
        .executableTarget(
            name: "CubitCLIExe",
            dependencies: ["Cubit"],
            path: "Executables/cubit"
        ),
        // `cubit-mcp` — the MCP server. One file: the `@main` that boots an `.accessory`
        // NSApplication (SwiftUI's ImageRenderer needs a live run loop for annotate) and hands
        // off to the library's `MCPServer`. The server's implementation lives in the shared
        // `Cubit` library (Sources/CubitMCP); this shim only starts it.
        .executableTarget(
            name: "CubitMCP",
            dependencies: ["Cubit"],
            path: "Executables/cubit-mcp"
        ),
        .testTarget(
            name: "CubitCLITests",
            dependencies: ["Cubit"],
            path: "Tests/CubitCLITests"
        ),
    ]
)
