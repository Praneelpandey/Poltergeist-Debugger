import RealityKit

// MARK: - CurseResolutionSystem

/// Per-frame RealityKit system that detects Fix-Entity proximity to Cursed
/// Entities and triggers curse resolution when distance ≤ snapRadius (Req 3.3–3.7).
///
/// ## Threading contract
/// update(context:) is NOT @MainActor-isolated — it runs on RealityKit's
/// internal render thread. All GameLoopState communication is routed through
/// CurseEventBuffer (NSLock-protected). Never call @MainActor methods here
/// (Steering §3.2, Req 3.6).
///
/// ## RKFix-Phase2 #2 — Lock Fix Entity on Snap
/// When resolution fires, we update the Fix Entity's DraggableComponent.restPosition
/// to the Cursed Entity's world position and set isSnapped = true.
/// This prevents DragReturnSystem from yanking the solved tool back to its
/// original spawn location (which would visually "un-fix" the puzzle).
///
/// ## RKFix-Phase2 #3 — Particle Emitter Sync
/// When isCursed flips to false, we immediately set the entity's
/// ParticleEmitterComponent.isEmitting = false so the green mist stops
/// in the same frame the resolution fires, with no 1-frame lag.
final class CurseResolutionSystem: System {

    // MARK: - Static queries (declared once, reused every frame — Steering §3.3)

    /// All entities that are (or were) cursed — both resolution targets
    /// (snapRadius > 0) and type-tag fix entities (snapRadius == 0).
    private static let cursedQuery = EntityQuery(
        where: .has(CurseStateComponent.self)
    )

    /// All player-draggable fix entities.
    private static let fixQuery = EntityQuery(
        where: .has(DraggableComponent.self)
    )

    // MARK: - Session state

    /// Tracks which curseTypes have already fired a resolution event this
    /// session to guarantee exactly one notification per type (Req 3.5).
    private var resolvedCurseTypes: Set<CurseType> = []

    private let eventBuffer: CurseEventBuffer

    // MARK: - Init

    // Registration is in PoltergeistDebuggerApp.init() — NOT here (RKFix 4).
    required init(scene: Scene) {
        self.eventBuffer = CurseEventBuffer.shared
    }

    // MARK: - Per-frame update

    func update(context: SceneUpdateContext) {

        // ── 1. Collect all live fix entities once per frame ──────────────
        // A fix entity carries DraggableComponent. We also read its
        // CurseStateComponent.curseType as the type-tag for matching.
        struct FixInfo {
            let entity:    Entity
            let curseType: CurseType
        }

        var fixInfos: [FixInfo] = []
        for entity in context.entities(matching: Self.fixQuery,
                                       updatingSystemWhen: .rendering) {
            guard let drag = entity.components[DraggableComponent.self],
                  !drag.isSnapped,                      // skip already-solved tools
                  let tag  = entity.components[CurseStateComponent.self]
            else { continue }
            fixInfos.append(FixInfo(entity: entity, curseType: tag.curseType))
        }

        // ── 2. Evaluate each resolution-target cursed entity ─────────────
        for cursedEntity in context.entities(matching: Self.cursedQuery,
                                             updatingSystemWhen: .rendering) {
            guard var curseState = cursedEntity.components[CurseStateComponent.self],
                  curseState.isCursed,
                  curseState.snapRadius > 0   // 0 == type-tag only; not a target
            else { continue }

            let origin = cursedEntity.position(relativeTo: nil)

            for fix in fixInfos {
                // Only the matching type triggers resolution (Req 5.4, 6.3).
                guard fix.curseType == curseState.curseType else { continue }

                // Self-resolution guard: the DanglingPointer drifter carries the
                // same curseType as its anchor — make sure we never compare an
                // entity against itself (RKFix 3 from design.md).
                guard fix.entity.id != cursedEntity.id else { continue }

                let fixPos = fix.entity.position(relativeTo: nil)
                let dist   = distance(fixPos, origin)

                guard dist <= curseState.snapRadius else { continue }

                // ── Resolution fires ──────────────────────────────────────

                // Mark the cursed entity resolved.
                curseState.isCursed = false
                cursedEntity.components[CurseStateComponent.self] = curseState

                // RKFix-Phase2 #3: stop particle emission immediately.
                if var particles = cursedEntity.components[ParticleEmitterComponent.self] {
                    particles.isEmitting = false
                    cursedEntity.components[ParticleEmitterComponent.self] = particles
                }

                // RKFix-Phase2 #2: lock the fix entity at the snap target so
                // DragReturnSystem never pulls it back to its original spawn.
                if var drag = fix.entity.components[DraggableComponent.self] {
                    drag.isSnapped    = true
                    drag.isReturning  = false
                    // Snap the fix entity visually to the cursed entity's position.
                    let snapPos = cursedEntity.position(relativeTo: fix.entity.parent)
                    drag.restPosition = cursedEntity.position(relativeTo: nil)
                    fix.entity.components[DraggableComponent.self] = drag
                    fix.entity.setPosition(snapPos, relativeTo: fix.entity.parent)
                }

                // Post exactly one event per curse type (Req 3.5).
                if !resolvedCurseTypes.contains(curseState.curseType) {
                    resolvedCurseTypes.insert(curseState.curseType)
                    eventBuffer.post(
                        CurseResolvedEvent(curseType: curseState.curseType)
                    )
                }

                // Done with this cursed entity; move to the next.
                break
            }
        }
    }
}
