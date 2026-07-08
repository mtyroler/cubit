import Observation

@MainActor
@Observable
final class AppState {
    var draftPercent: String?
}
