/// JSON Schemas for the four tools' inputs, authored inline as JSON string literals and parsed
/// once into `JSONValue` for `tools/list`. Kept as text (not built out of `JSONValue` cases) so
/// the schemas read like the JSON an agent actually sees.
enum Schemas {
    static let listWindows = """
    {
      "type": "object",
      "properties": {
        "onScreenOnly": {
          "type": "boolean",
          "description": "Reserved. Window listing is always on-screen-only; accepted for forward compatibility."
        }
      },
      "additionalProperties": false
    }
    """

    // Shared fragments -------------------------------------------------------

    private static let pointFragment = """
    { "type": "object", "properties": { "x": { "type": "number" }, "y": { "type": "number" } }, "required": ["x", "y"] }
    """

    private static let rectFragment = """
    { "type": "object",
      "properties": { "x": { "type": "number" }, "y": { "type": "number" }, "width": { "type": "number" }, "height": { "type": "number" } },
      "required": ["x", "y", "width", "height"] }
    """

    /// A single measurement region (rectangle needs `rect`; a line needs two `endpoints`).
    private static func regionItem(space: String) -> String {
        """
        { "type": "object",
          "description": "One region. kind=rectangle uses rect; kind=horizontal|vertical uses two endpoints. Coordinates in \(space).",
          "properties": {
            "kind": { "type": "string", "enum": ["rectangle", "horizontal", "vertical"] },
            "rect": \(rectFragment),
            "endpoints": { "type": "array", "items": \(pointFragment), "minItems": 2, "maxItems": 2 },
            "label": { "type": "string" },
            "colorIndex": { "type": "integer", "description": "Palette index 0–7; defaults to the region's position." }
          },
          "required": ["kind"] }
        """
    }

    private static func referenceObject(required: Bool) -> String {
        """
        { "type": "object",
          "description": "Reference frame — provide exactly one of window / screen / rect.\(required ? "" : " Defaults to the display containing the region.")",
          "properties": {
            "window": { "type": ["integer", "string"], "description": "Window number, or a case-insensitive app/title substring." },
            "screen": { "type": "integer", "description": "Display index (0 = main), CGGetActiveDisplayList order." },
            "rect": \(rectFragment)
          } }
        """
    }

    // measure_region --------------------------------------------------------

    static var measureRegion: String {
        """
        {
          "type": "object",
          "properties": {
            "region": {
              "type": "object",
              "description": "The region to measure, in CANONICAL coordinates (points, top-left origin, y-down) — the same space list_windows frames use.",
              "properties": {
                "kind": { "type": "string", "enum": ["rectangle", "horizontal", "vertical"] },
                "rect": \(rectFragment),
                "endpoints": { "type": "array", "items": \(pointFragment), "minItems": 2, "maxItems": 2 }
              },
              "required": ["kind"]
            },
            "reference": \(referenceObject(required: false)),
            "scale": { "type": "number", "description": "Point-to-pixel scale for the px sizes; defaults to the reference display's backing scale (typically 2)." }
          },
          "required": ["region"]
        }
        """
    }

    // annotate_screenshot ---------------------------------------------------

    static var annotateScreenshot: String {
        """
        {
          "type": "object",
          "properties": {
            "imagePath": { "type": "string", "description": "Path to the input image (PNG or any ImageIO-readable format). Provide this OR imageBase64." },
            "imageBase64": { "type": "string", "description": "Base64 input image bytes (data: URLs accepted). Provide this OR imagePath." },
            "regions": {
              "type": "object",
              "description": "Measurement regions in IMAGE PIXELS (top-left origin, y-down).",
              "properties": {
                "scale": { "type": "number", "description": "Point-to-pixel scale of the image (default 2)." },
                "reference": {
                  "type": "object",
                  "description": "Optional sub-rect to measure against; omit to measure against the whole image.",
                  "properties": { "rect": \(rectFragment) }
                },
                "regions": { "type": "array", "items": \(regionItem(space: "image pixels")), "minItems": 1 }
              },
              "required": ["regions"]
            },
            "outputPath": { "type": "string", "description": "Where to write the annotated PNG. If omitted, the PNG is returned inline as a base64 image block." },
            "sidecar": { "type": "boolean", "description": "When writing to outputPath, also write the MeasurementSidecar JSON beside it (same basename, .json)." },
            "totals": { "type": "boolean", "description": "Render summed per-kind totals in the legend." },
            "scale": { "type": "number", "description": "Point-to-pixel scale. Precedence: this > regions.scale > 2." }
          },
          "required": ["regions"]
        }
        """
    }

    // analyze_dead_space ----------------------------------------------------

    static var analyzeDeadSpace: String {
        """
        {
          "type": "object",
          "properties": {
            "target": \(referenceObject(required: true)),
            "content": {
              "type": "array",
              "description": "The content/used regions you have already measured, in CANONICAL points. Rectangles contribute area; lines contribute zero.",
              "items": \(regionItem(space: "canonical points"))
            },
            "scale": { "type": "number", "description": "Point-to-pixel scale for the px areas; defaults to the target display's backing scale." }
          },
          "required": ["target", "content"]
        }
        """
    }
}
