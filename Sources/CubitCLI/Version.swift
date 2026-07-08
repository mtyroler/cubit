/// The `cubit` CLI's own version string. This is INTENTIONALLY independent of the app's
/// `MARKETING_VERSION` (an Xcode build setting the SwiftPM tool can't read) — bump it by hand
/// when cutting a CLI release. Keep it in sync with the app's version at release time.
enum CubitCLIVersion {
    static let current = "0.3.0"
}
