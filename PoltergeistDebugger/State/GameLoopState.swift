import Observation

// MARK: - GameLoopState

/// The single source of truth for game session state, observable by SwiftUI.
///
/// ## Isolation
/// Declared @MainActor so every property read and write is guaranteed to occur
/// on the main thread — safe for SwiftUI observation without extra synchronisation.
///
/// ## How it receives ECS events
/// CurseResolutionSystem writes resolved events to CurseEventBuffer (off-actor).
/// The RealityView `update:` closure (on @MainActor) calls processEvents() each
/// frame, which drains the buffer and mutates this class's properties.
/// This is the only legal ECS → SwiftUI communication path (Steering §2.2).
@Observable
@MainActor
final class GameLoopState {

    // MARK: - Published State

    /// Current phase of the AR game session.
    /// Observed by ContentView to show/hide HUD layers (Req 1.7, 10.3).
    var sessionPhase: SessionPhase = .scanning

    /// Number of resolved puzzles; always in the range 0...3.
    /// private(set) so only this class can increment it (Req 10.1).
    private(set) var resolvedCount: Int = 0

    /// CurseTypes whose isCursed is still true.
    /// Observed by HUDView to list active curses (Req 10.2).
    var activeCurses: [CurseType] = CurseType.allCases

    // MARK: - Dependencies

    /// The buffer that CurseResolutionSystem writes to.
    /// Injected at init so tests can supply an isolated instance.
    let eventBuffer: CurseEventBuffer

    init(eventBuffer: CurseEventBuffer = .shared) {
        self.eventBuffer = eventBuffer
    }

    // MARK: - Event Processing

    /// Drain all pending ECS events and update published state.
    ///
    /// Called from the RealityView `update:` closure every render frame.
    /// Keeps the closure lightweight: drainEvents() holds the lock only
    /// long enough to swap the buffer, then releases before we iterate.
    func processEvents() {
        let events = eventBuffer.drainEvents()
        for event in events {
            handleResolution(of: event.curseType)
        }
    }

    // MARK: - Private Mutation

    /// Apply one puzzle-resolution event to the observable state.
    ///
    /// Guards against processing events after victory (Req 10.7).
    /// Clamps resolvedCount to 3 as a defensive invariant (Req 10.1).
    private func handleResolution(of curseType: CurseType) {
        // Req 10.7: once in victory, all subsequent events are ignored.
        guard sessionPhase != .victory else { return }

        // Remove from the active list. removeAll is idempotent if the type
        // was already removed (protects against duplicate events for the same type).
        activeCurses.removeAll { $0 == curseType }

        // Req 10.1: resolvedCount is bounded [0, 3].
        resolvedCount = min(resolvedCount + 1, 3)

        // Req 10.3: transition to victory as soon as the third puzzle resolves.
        if resolvedCount == 3 {
            sessionPhase = .victory
        }
    }

    // MARK: - Restart (Req 10.6)

    /// Reset all state to the initial playing configuration.
    ///
    /// Called by VictoryOverlayView's restart button.
    /// Does NOT require an app relaunch — all puzzle entity resets are driven
    /// by observers of sessionPhase and activeCurses elsewhere in the system.
    func restartSession() {
        resolvedCount = 0
        activeCurses  = CurseType.allCases
        sessionPhase  = .playing
        // Discard any stale events that arrived between the last resolve and now.
        _ = eventBuffer.drainEvents()
    }

    // MARK: - Internal setter (used by GameStatePersistence.restore only)

    /// Directly sets resolvedCount without firing resolution events.
    ///
    /// Called once during foreground restore, before the ECS systems start
    /// processing new events. Not part of the normal event-driven path.
    func resetResolvedCount(to count: Int) {
        resolvedCount = count
    }
}
