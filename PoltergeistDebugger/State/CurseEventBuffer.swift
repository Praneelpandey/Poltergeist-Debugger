import Foundation

// MARK: - CurseResolvedEvent

/// Value type emitted by CurseResolutionSystem when a curse is resolved.
///
/// Sendable: struct with only Sendable fields (CurseType, Date).
/// Equatable: used in property-based tests to verify buffer completeness.
struct CurseResolvedEvent: Sendable, Equatable {
    let curseType: CurseType
    let timestamp: Date

    init(curseType: CurseType, timestamp: Date = .now) {
        self.curseType = curseType
        self.timestamp = timestamp
    }
}

// MARK: - CurseEventBuffer

/// Thread-safe FIFO queue that bridges CurseResolutionSystem (off @MainActor)
/// to GameLoopState (@MainActor) without either side blocking the other.
///
/// ## Threading contract
/// - `post(_:)` is called from RealityKit's system thread (not @MainActor).
/// - `drainEvents()` is called from the RealityView `update:` closure (@MainActor).
/// - An NSLock serialises both operations so no event is lost or doubled.
///
/// ## Why @unchecked Sendable?
/// Swift's type system cannot verify that NSLock correctly protects `pending`.
/// The lock is the correctness mechanism; `@unchecked` acknowledges that we
/// are taking manual responsibility for thread safety (Steering §2.4).
final class CurseEventBuffer: @unchecked Sendable {

    // Shared singleton used in production. Tests create isolated instances.
    static let shared = CurseEventBuffer()

    // Internal lock — all reads and writes to `pending` must be inside lock.withLock { }.
    private let lock = NSLock()

    // The backing store. Never accessed outside lock.withLock { }.
    private var pending: [CurseResolvedEvent] = []

    // MARK: - Writing (called off @MainActor)

    /// Appends one event to the buffer.
    /// O(1) amortised. Safe to call from any thread.
    func post(_ event: CurseResolvedEvent) {
        lock.withLock {
            pending.append(event)
        }
    }

    // MARK: - Reading (called on @MainActor)

    /// Atomically removes and returns all pending events.
    ///
    /// The swap is O(n) in the number of events but O(1) in lock-hold time:
    /// we capture the array, clear `pending`, then release the lock before
    /// returning — so `post` is never blocked by the caller processing events.
    ///
    /// A second call immediately after this one returns an empty array,
    /// which is the property tested by Property 4.
    func drainEvents() -> [CurseResolvedEvent] {
        lock.withLock {
            let events = pending
            pending = []
            return events
        }
    }
}
