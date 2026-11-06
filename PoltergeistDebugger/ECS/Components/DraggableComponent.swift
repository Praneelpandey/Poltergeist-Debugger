import RealityKit

// MARK: - DraggableComponent

/// Marks an entity as eligible for SwiftUI DragGesture input (Req 3.2).
///
/// Only entities carrying this component respond to drag gestures.
/// All state transitions are driven by DragHandler (@MainActor) and
/// DragReturnSystem (off-actor, per-frame).
///
/// NOT Codable: SIMD3<Float> does not conform to Codable by default.
/// Transform snapshots for persistence are handled by EntityTransformSnapshot.
///
/// Pure data — no methods, no SwiftUI references (Steering §3.1).
struct DraggableComponent: Component {

    // MARK: - Stored Properties

    /// World-space resting position. The entity animates back here when
    /// released outside a Snap Zone (Req 4.6).
    /// Updated to the snap target's position when the entity is snapped
    /// so DragReturnSystem never pulls a solved tool back (RKFix-Phase2 #2).
    var restPosition: SIMD3<Float>

    /// True while the player's finger is actively dragging this entity.
    /// Set to true on the first onChanged callback; false on onEnded.
    var isDragging: Bool

    /// True while DragReturnSystem is animating this entity back to restPosition.
    ///
    /// ## Why this flag exists (RKFix-Phase2 #1)
    /// DragReturnSystem.update(context:) runs at 60 fps. Without this flag,
    /// entity.move(to:relativeTo:duration:) would be called on every frame of
    /// the return journey, restarting the animation each time and causing the
    /// entity to stutter in place. The flag ensures move() is called exactly once,
    /// and DragReturnSystem clears it when the entity reaches restPosition.
    var isReturning: Bool

    /// True once the entity has been snapped into its Snap Zone and the curse
    /// has been resolved. DragReturnSystem skips snapped entities entirely;
    /// they stay at their resolved position.
    ///
    /// Also signals CurseResolutionSystem to stop re-evaluating this Fix Entity
    /// (avoids post-resolution churn each frame).
    var isSnapped: Bool

    /// Brightness multiplier captured at entity-creation time so that the
    /// 30% boost applied during drag (Req 4.4) can be precisely reversed on drop.
    var originalBrightness: Float

    // MARK: - Init

    /// - Parameters:
    ///   - restPosition: World-space position the entity returns to after release.
    ///   - originalBrightness: Idle brightness multiplier; defaults to 1.0.
    init(restPosition: SIMD3<Float>, originalBrightness: Float = 1.0) {
        self.restPosition       = restPosition
        self.isDragging         = false
        self.isReturning        = false
        self.isSnapped          = false
        self.originalBrightness = originalBrightness
    }
}
