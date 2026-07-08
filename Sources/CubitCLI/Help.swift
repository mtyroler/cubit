/// Help text for every command. Printed to stdout on `--help`; usage errors print a one-line
/// hint to stderr instead. Exit codes are documented here because agents branch on them.
enum Help {
    static let top = """
    cubit \(CubitCLIVersion.current) — measure and annotate anything on screen, for agents.

    USAGE:
      cubit <command> [options]

    COMMANDS:
      windows     List on-screen windows as JSON (number, app, title, frame, scale).
      capture     Save a frozen PNG of a window or a display.
      annotate    Render Cubit-style measurement annotations onto an existing image.

    GLOBAL:
      --help, -h      Show help (also available per command: cubit <command> --help).
      --version, -V   Print the CLI version.

    OUTPUT:
      Machine-readable results go to stdout as pretty, sorted-key JSON. Human and error
      text goes to stderr.

    EXIT CODES:
      0  success
      1  generic failure
      2  usage error (bad flags/arguments)
      3  permission denied (grant Screen Recording, then re-run)
      4  not found / ambiguous (no matching window, index out of range, missing file)
    """

    static let windows = """
    cubit windows — list on-screen windows as JSON.

    USAGE:
      cubit windows [--json]

    OPTIONS:
      --json    Emit JSON (the default and only format; accepted for explicitness).

    NOTES:
      Windows are listed front-to-back ("order" 0 = frontmost). Each entry has the window
      number, owner app, title, window layer, canonical frame (points, top-left origin,
      y-down), and the scale factor of the display it sits on. Without a Screen Recording
      grant macOS hides window titles — the top-level "permission.screenRecording" flag
      reports whether the grant is present.
    """

    static let capture = """
    cubit capture — save a frozen PNG of a window or a display.

    USAGE:
      cubit capture --window <name-or-number> [-o out.png]
      cubit capture --screen [index] [-o out.png]

    OPTIONS:
      --window, -w <q>   Case-insensitive substring of "app title", or an exact window
                         number. Ambiguous matches list candidates and exit 4.
      --screen [index]   Capture a display; index defaults to 0 (main). Indices follow
                         the system display order (CGGetActiveDisplayList; main first).
      --out, -o <path>   Output PNG path. Defaults to a timestamped name in the current
                         directory.

    NOTES:
      Requires Screen Recording permission (exit 3 if missing). Window mode captures the
      window's own pixels, so an overlapping window never bleeds in. Output PNGs are
      metadata-free (no EXIF/DPI/text chunks). Prints {output,pixelWidth,pixelHeight,scale}
      as JSON on success.
    """

    static let annotate = """
    cubit annotate — render measurement annotations onto an existing image.

    USAGE:
      cubit annotate --in shot.png --regions regions.json -o out.png [--scale N]
                     [--sidecar] [--totals]

    OPTIONS:
      --in, -i <path>       Input image (PNG or any ImageIO-readable format).
      --regions, -r <path>  Regions JSON (see SCHEMA). Coordinates are in image pixels.
      --out, -o <path>      Output PNG path (required).
      --scale N             Point/pixel scale. Precedence: --scale > regions "scale" > 2.
      --sidecar             Also write the M1 MeasurementSidecar JSON next to the output
                            (same basename, .json extension).
      --totals              Render summed per-kind totals in the legend.

    SCHEMA (regions.json — all coordinates in IMAGE PIXELS, top-left origin):
      {
        "scale": 2,
        "reference": { "rect": { "x": 0, "y": 0, "width": 2400, "height": 1600 } },
        "regions": [
          { "kind": "rectangle",
            "rect": { "x": 200, "y": 240, "width": 600, "height": 400 },
            "label": "hero", "colorIndex": 0 },
          { "kind": "horizontal",
            "endpoints": [ { "x": 200, "y": 800 }, { "x": 1400, "y": 800 } ] },
          { "kind": "vertical",
            "endpoints": [ { "x": 200, "y": 200 }, { "x": 200, "y": 1000 } ] }
        ]
      }

      - "reference" is optional; omit it to measure against the whole image. A sub-rect
        draws the dashed reference outline.
      - "label" and "colorIndex" are optional. colorIndex defaults to the region's position
        and wraps through Cubit's 8-color palette.
      - A horizontal line's endpoints must share y; a vertical line's must share x.

    NOTES:
      Uses the same layout engine and drawing pipeline as an app export, so output matches
      the app pixel-for-pixel. Output PNGs are metadata-free.
    """
}
