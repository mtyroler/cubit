import Observation

@MainActor
@Observable
final class AppState {
    var draftPercent: String?
    /// True once a frozen capture is available, so export can produce a clean image.
    var captureAvailable = false
}
