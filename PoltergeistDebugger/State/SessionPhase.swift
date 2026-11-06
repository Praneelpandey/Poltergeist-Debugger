// MARK: - SessionPhase

/// The top-level game session state machine, owned by GameLoopState.
///
/// Conforms to String (raw-value encoding), Codable (persistence via
/// PersistedGameState.sessionPhase), and Sendable (safe to pass across
/// actor boundaries, e.g. from ARSessionCoordinator to GameLoopState).
enum SessionPhase: String, Codable, Sendable {

    /// ARKit is searching for a suitable horizontal plane.
    /// HUD displays the scanning indicator (Req 1.5).
    case scanning

    /// The Motherboard has been anchored; all three puzzles are live.
    /// Entered when ARSessionCoordinator detects a plane ≥ 0.09 m² (Req 1.7).
    case playing

    /// All three puzzles are resolved.
    /// Entered by GameLoopState.handleResolution when resolvedCount reaches 3 (Req 10.3).
    case victory
}
