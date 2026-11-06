import Foundation

// MARK: - GameStatePersistence

/// Thread-safe Swift actor that owns all disk I/O for game-state persistence.
///
/// ## Why an actor?
/// GameLoopState is @MainActor. The persistence layer must be callable from
/// @MainActor contexts (ContentView.onChange) without blocking the main thread
/// and without data races on file handles. A Swift actor serialises calls on
/// its own executor, so concurrent save/load calls are automatically queued.
///
/// ## File location (Req 11.3)
/// Documents/poltergeist_save.json — inside the app sandbox, survives app
/// updates, excluded from iCloud backup by default.
///
/// ## Error handling (Req 11.4, 11.7)
/// - save(_:) throws on encoding or write failure so ContentView can
///   surface an error indicator to the player within 3 s (Req 11.7).
/// - load() returns nil (never throws) when the file is absent, malformed,
///   or has a mismatched schema version. The corrupted file is deleted.
actor GameStatePersistence {

    static let shared = GameStatePersistence()

    // MARK: - Private

    private let saveURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("poltergeist_save.json")
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder = JSONDecoder()

    // MARK: - Public interface

    /// Encode `state` and write atomically to Documents/poltergeist_save.json.
    ///
    /// `.atomicWrite` writes to a temp file then renames — ensures the existing
    /// save is never partially overwritten if the app is killed mid-write (Req 11.7).
    ///
    /// - Throws: Any encoding or file-system error.
    func save(_ state: PersistedGameState) throws {
        let data = try encoder.encode(state)
        try data.write(to: saveURL, options: .atomicWrite)
    }

    /// Load and decode the save file.
    ///
    /// Returns nil — and deletes the file — in three cases (Req 11.4):
    ///   1. The file does not exist (normal first launch).
    ///   2. The JSON is malformed (corrupted file).
    ///   3. schemaVersion != PersistedGameState.currentSchemaVersion.
    ///
    /// In cases 2 and 3, a warning is printed to the system log. The caller
    /// initialises a fresh GameLoopState when nil is returned.
    func load() -> PersistedGameState? {
        guard FileManager.default.fileExists(atPath: saveURL.path) else {
            return nil
        }
        do {
            let data  = try Data(contentsOf: saveURL)
            let state = try decoder.decode(PersistedGameState.self, from: data)

            guard state.schemaVersion == PersistedGameState.currentSchemaVersion else {
                try? FileManager.default.removeItem(at: saveURL)
                print("[Persistence] Schema mismatch (stored \(state.schemaVersion), " +
                      "current \(PersistedGameState.currentSchemaVersion)) — discarding save.")
                return nil
            }
            return state

        } catch {
            try? FileManager.default.removeItem(at: saveURL)
            print("[Persistence] Malformed save file: \(error) — discarding.")
            return nil
        }
    }

    // MARK: - GameLoopState restore helper

    /// Apply a successfully loaded PersistedGameState back onto a live GameLoopState.
    ///
    /// Must be called on @MainActor because GameLoopState is @MainActor-isolated.
    /// ContentView calls this inside a Task { @MainActor in } on foreground transition.
    @MainActor
    static func restore(_ saved: PersistedGameState, into state: GameLoopState) {
        // Restore session phase (fall back to .playing if raw value is unrecognised).
        state.sessionPhase = SessionPhase(rawValue: saved.sessionPhase) ?? .playing

        // Rebuild activeCurses from the inverse of resolvedPuzzles.
        state.activeCurses = CurseType.allCases.filter { type in
            saved.resolvedPuzzles[type.rawValue] != true
        }

        // Recalculate resolvedCount from resolvedPuzzles (source of truth).
        // We don't persist resolvedCount directly to avoid the count going
        // out of sync with activeCurses on a malformed file edge case.
        let resolved = saved.resolvedPuzzles.values.filter { $0 }.count
        // resolvedCount is private(set); use the dedicated setter path via
        // handleResolution — but that would fire events. Instead we reset
        // to 0 and then bump directly. Because this runs on @MainActor and
        // the ECS systems have not started yet, there is no concurrency risk.
        state.resetResolvedCount(to: min(resolved, 3))
    }
}
