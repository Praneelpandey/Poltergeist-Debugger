import Foundation

// MARK: - PersistedGameState

/// Top-level Codable payload written to Documents/poltergeist_save.json.
///
/// ## Schema versioning (Req 11.6)
/// `schemaVersion` is an integer incremented whenever the shape of this struct
/// changes. GameStatePersistence.load() discards the file and returns nil if
/// the stored version differs from `currentSchemaVersion`, preventing silent
/// data corruption across app updates.
///
/// ## Field coverage (Req 11.1)
/// - resolvedPuzzles  — which of the three curses have been fixed
/// - entitySnapshots  — world-space transforms for named entities (for visual restore)
/// - sessionPhase     — scanning / playing / victory raw string
///
/// ## Round-trip property (Req 11.5)
/// All fields are Codable primitives (Int, Bool, Float, String), so
/// encode→decode is lossless. Property 1 verifies this across arbitrary inputs.
struct PersistedGameState: Codable, Equatable {

    /// Increment this constant — and add a migration note — whenever the
    /// struct's stored properties change shape (Req 11.6).
    static let currentSchemaVersion: Int = 1

    /// Must equal currentSchemaVersion for the file to be accepted.
    let schemaVersion: Int

    /// Key: CurseType.rawValue ("memoryLeak", "raceCondition", "danglingPointer")
    /// Value: true if that puzzle has been resolved.
    var resolvedPuzzles: [String: Bool]

    /// Key: entity name (matches Entity.name set in PuzzleFactory)
    /// Value: flattened Transform snapshot
    var entitySnapshots: [String: EntityTransformSnapshot]

    /// SessionPhase.rawValue — "scanning", "playing", or "victory".
    var sessionPhase: String

    // MARK: - Factory from live GameLoopState

    /// Snapshot the current GameLoopState into a persistable value.
    ///
    /// `entitySnapshots` is supplied by the caller because GameLoopState does
    /// not hold entity references; ContentView provides them at save time.
    init(from state: GameLoopState,
         entitySnapshots: [String: EntityTransformSnapshot]) {
        self.schemaVersion    = Self.currentSchemaVersion
        self.resolvedPuzzles  = Dictionary(
            uniqueKeysWithValues: CurseType.allCases.map { type in
                (type.rawValue, !state.activeCurses.contains(type))
            }
        )
        self.entitySnapshots  = entitySnapshots
        self.sessionPhase     = state.sessionPhase.rawValue
    }

    // MARK: - Memberwise init (used in tests and GameStatePersistence.load)

    init(schemaVersion: Int,
         resolvedPuzzles: [String: Bool],
         entitySnapshots: [String: EntityTransformSnapshot],
         sessionPhase: String) {
        self.schemaVersion   = schemaVersion
        self.resolvedPuzzles = resolvedPuzzles
        self.entitySnapshots = entitySnapshots
        self.sessionPhase    = sessionPhase
    }
}
