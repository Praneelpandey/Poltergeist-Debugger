import RealityKit

// MARK: - DragReturnSystem

/// Per-frame system that animates released Fix Entities back to their resting
/// position using an ease-out curve (Req 4.6, 4.7).
///
/// ## RKFix-Phase2 #1 — Preventing animation spam
/// This system runs at ~60 fps. The naive approach — calling entity.move(to:)
/// every frame while position ≠ restPosition — would restart the animation
/// every frame, causing the entity to jitter in place.
///
/// The fix: DraggableComponent.isReturning is a one-shot latch.
///   • isReturning = false, !isDragging, !isSnapped, dist > threshold
///       → call entity.move(to:) ONCE, set isReturning = true
///   • isReturning = true
///       → skip: animation is already in flight
///   • dist ≤ arrival threshold while isReturning = true
///       → clear isReturning = false (animation complete)
///   • isDragging becomes true again
///       → clear isReturning = false (drag interrupted the return)
///
/// ## Why 0.005 m as the arrival threshold?
/// RealityKit's animation system may not land exactly on the target position
/// before stopping. 5 mm is imperceptible at AR scale and avoids the system
/// perpetually re-triggering because floating-point equality never hits zero.
final class DragReturnSystem: System {

    private static let draggableQuery = EntityQuery(
        where: .has(DraggableComponent.self)
    )

    /// Distance below which we consider the entity to have arrived (metres).
    private static let arrivalThreshold: Float = 0.005

    /// Return animation duration (seconds). Req 4.6 specifies 0.2–0.5 s.
    private static let returnDuration: TimeInterval = 0.35

    // Registration is in PoltergeistDebuggerApp.init() — NOT here (RKFix 4).
    required init(scene: Scene) {}

    // MARK: - Per-frame update

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.draggableQuery,
                                       updatingSystemWhen: .rendering) {

            guard var drag = entity.components[DraggableComponent.self] else { continue }

            // ── Case: currently being dragged ────────────────────────────
            // If drag restarted mid-return, cancel the latched state so a
            // fresh return triggers correctly when the player releases again.
            if drag.isDragging {
                if drag.isReturning {
                    drag.isReturning = false
                    entity.components[DraggableComponent.self] = drag
                }
                continue
            }

            // ── Case: snapped — leave it exactly where CurseResolutionSystem put it.
            if drag.isSnapped { continue }

            // ── Case: return animation already in flight ─────────────────
            if drag.isReturning {
                // Check if we have arrived.
                let currentPos = entity.position(relativeTo: nil)
                let dist = distance(currentPos, drag.restPosition)
                if dist <= Self.arrivalThreshold {
                    // Arrived — snap precisely and clear the latch.
                    entity.setPosition(drag.restPosition, relativeTo: nil)
                    drag.isReturning = false
                    entity.components[DraggableComponent.self] = drag
                }
                // Either way, don't re-trigger move().
                continue
            }

            // ── Case: released and not yet returning ─────────────────────
            let currentPos = entity.position(relativeTo: nil)
            let dist = distance(currentPos, drag.restPosition)

            guard dist > Self.arrivalThreshold else { continue }

            // Trigger the ease-out return animation exactly once.
            var targetTransform = entity.transform
            targetTransform.translation = drag.restPosition

            entity.move(
                to: targetTransform,
                relativeTo: nil,
                duration: Self.returnDuration,
                timingFunction: .easeOut
            )

            // Latch — subsequent frames skip until arrival or new drag.
            drag.isReturning = true
            entity.components[DraggableComponent.self] = drag
        }
    }
}
