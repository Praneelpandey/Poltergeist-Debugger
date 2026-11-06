import RealityKit
import SwiftUI

// MARK: - DragHandler

/// @MainActor class that translates SwiftUI DragGesture events into
/// world-space entity movement (Req 4.1, 4.4, 4.6, 4.7).
///
/// ## How 2D touch → 3D world position works
/// EntityTargetValue<DragGesture.Value> carries a `location3D: Point3D`
/// property that RealityKit populates by projecting the 2D touch point
/// through the camera's view frustum onto a plane at the entity's current
/// depth. `value.convert(_:from:to:)` then transforms that Point3D from
/// the gesture's local coordinate space into the RealityKit scene's world
/// coordinate space. See the explanation in the README / task walkthrough.
///
/// ## The one-time vs. every-frame split (RKFix-Phase2 #1)
/// isDragging == false on the FIRST onChanged callback:
///   → apply brightness boost, fire pickup haptic, set isDragging = true.
/// isDragging == true on ALL subsequent onChanged callbacks (same drag):
///   → only update world position. No repeated boost/haptic.
@MainActor
final class DragHandler {

    // MARK: - onChanged

    /// Called every frame while the player's finger is moving.
    func handleChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        guard var draggable = value.entity.components[DraggableComponent.self],
              !draggable.isSnapped   // resolved tools are no longer draggable
        else { return }

        // ── One-time setup on the very first callback of a new drag ──────
        if !draggable.isDragging {
            draggable.isDragging  = true
            draggable.isReturning = false   // cancel any in-flight return animation
            value.entity.components[DraggableComponent.self] = draggable

            // Brightness boost: +30% above idle (Req 4.4).
            applyBrightnessBoost(to: value.entity,
                                 multiplier: draggable.originalBrightness * 1.3)

            // Pickup haptic (Req 8.3) — Phase 4 wires the real HapticEngine;
            // the call site is here so Phase 4 only needs to uncomment one line.
            // HapticEngine.shared.playPickup()
        }

        // ── Every frame: move entity to current finger position ──────────
        // value.location3D is in the gesture's local coordinate space.
        // convert(_:from:to:) maps it into RealityKit scene (world) space.
        let worldPos = value.convert(value.location3D, from: .local, to: .scene)
        value.entity.setPosition(SIMD3<Float>(worldPos), relativeTo: nil)
    }

    // MARK: - onEnded

    /// Called once when the player lifts their finger.
    func handleEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        guard var draggable = value.entity.components[DraggableComponent.self],
              !draggable.isSnapped
        else { return }

        draggable.isDragging = false
        // isReturning stays false here — DragReturnSystem sets it to true
        // on the next frame when it detects isDragging == false and
        // dist > arrivalThreshold, triggering the ease-out animation.
        value.entity.components[DraggableComponent.self] = draggable

        // Remove brightness boost.
        applyBrightnessBoost(to: value.entity,
                             multiplier: draggable.originalBrightness)
    }

    // MARK: - Brightness helper

    /// Sets the emissive/base-color intensity on all ModelEntity descendants.
    ///
    /// We walk the entity tree because a fix entity might be a parent whose
    /// visible geometry lives in a child ModelEntity.
    private func applyBrightnessBoost(to entity: Entity, multiplier: Float) {
        if let model = entity as? ModelEntity {
            model.model?.materials = model.model?.materials.map { material in
                guard var pbr = material as? PhysicallyBasedMaterial else {
                    return material
                }
                // Scale the emissive colour intensity.
                // For unlit materials (SimpleMaterial) this is a no-op;
                // Phase 4 can swap to proper PBR materials with emission.
                pbr.emissiveIntensity = multiplier
                return pbr
            } ?? []
        }
        for child in entity.children {
            applyBrightnessBoost(to: child, multiplier: multiplier)
        }
    }
}
