import RealityKit

// MARK: - DraggableComponent

/// Marks an entity as eligible for SwiftUI DragGesture input (Req 3.2).
///
/// Only entities carrying this component respond to drag gestures.
/// The gesture handler reads and writes isDragging each frame.
///
/// NOT Codable: SIMD3<Float> does not conform to Codable by default.
/// Transform snapshots for persistence are handled separately by
/// EntityTransformSnapshot in the Persistence layer.
///
/// This component is pure data — no methods, no SwiftUI references.
struct DraggableComponent: Component {

    /// World-space resting position. The entity animates back here when
    /// released outside a Snap Zone (Req 4.6).
    ///
    /// Stored as three separate scalars is an alternative if Codable is
    /// ever needed; for now SIMD3<Float> is the authoritative representation.
    var restPosition: SIMD3<Float>

    /// True while the player's finger is actively dragging this entity.
    /// Set to true by DragHandler.handleChanged on the first callback of a drag;
    /// set to false by DragHandler.handleEnded.
    var isDragging: Bool

    /// Brightness multiplier captured at entity-creation time so that the
    /// 30% boost applied during drag (Req 4.4) can be precisely reversed on drop.
    var originalBrightness: Float

    /// - Parameters:
    ///   - restPosition: World-space position the entity returns to after release.
    ///   - originalBrightness: Idle brightness multiplier; defaults to 1.0.
    init(restPosition: SIMD3<Float>, originalBrightness: Float = 1.0) {
        self.restPosition       = restPosition
        self.isDragging         = false
        self.originalBrightness = originalBrightness
    }
}
