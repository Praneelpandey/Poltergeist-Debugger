import RealityKit

// MARK: - PuzzleFactory

/// Static factory namespace that constructs fully configured RealityKit entity
/// trees for each puzzle (Task 8.1, design.md §7).
///
/// All component attachment happens here; view code never touches components.
enum PuzzleFactory {

    // MARK: - Motherboard root

    /// Creates the root Motherboard entity and attaches all puzzle sub-trees.
    ///
    /// Phase 2 adds makeMemoryLeakPuzzle().
    /// Phase 3 adds makeRaceConditionPuzzle() and makeDanglingPointerPuzzle().
    static func makeMotherboard() -> Entity {
        let root = Entity()
        root.name = "Motherboard"
        root.addChild(makeMemoryLeakPuzzle())
        // Phase 3: root.addChild(makeRaceConditionPuzzle())
        // Phase 3: root.addChild(makeDanglingPointerPuzzle())  — note: drifter added at world level
        return root
    }

    // MARK: - Puzzle 1: Memory Leak

    /// Returns the Memory Leak puzzle sub-tree.
    ///
    /// **Cursed entity — RAM bank:**
    /// - CurseStateComponent(.memoryLeak, snapRadius: 0.12)
    /// - ParticleEmitterComponent (green mist, emission = true while isCursed)
    ///
    /// **Fix entity — Deallocator:**
    /// - DraggableComponent
    /// - CurseStateComponent(.memoryLeak, snapRadius: 0.0)  ← type-tag only
    /// - InputTargetComponent   ← required for DragGesture hit-testing (RKFix 1)
    /// - CollisionComponent     ← required for DragGesture hit-testing (RKFix 1)
    static func makeMemoryLeakPuzzle() -> Entity {
        let root = Entity()
        root.name = "MemoryLeakPuzzle"

        // ── RAM bank (cursed entity) ──────────────────────────────────────
        let ram = ModelEntity(
            mesh:      .generateBox(size: 0.08),
            materials: [SimpleMaterial(color: .green, isMetallic: true)]
        )
        ram.name     = MemoryLeakPuzzle.ramBankName
        ram.position = SIMD3<Float>(0, 0.04, -0.10)
        ram.components.set(CurseStateComponent(curseType: .memoryLeak, snapRadius: 0.12))
        ram.components.set(MemoryLeakPuzzle.makeGreenParticleEmitter())
        // CollisionComponent on the RAM bank allows the Deallocator's collision
        // shape to register contact events (Req 5.5) in Phase 2+.
        ram.components.set(CollisionComponent(
            shapes: [.generateBox(size: SIMD3<Float>(0.08, 0.08, 0.08))]
        ))

        // ── Deallocator (fix entity) ──────────────────────────────────────
        let deallocator = ModelEntity(
            mesh:      .generateSphere(radius: 0.025),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        deallocator.name = MemoryLeakPuzzle.deallocatorName

        // Rest position: to the right of the RAM bank, easy to reach.
        let restPos = SIMD3<Float>(0.18, 0.04, -0.10)
        deallocator.position = restPos

        // Draggable state
        deallocator.components.set(DraggableComponent(restPosition: restPos))

        // Type tag — snapRadius: 0.0 means this entity is never a resolution target;
        // CurseResolutionSystem only evaluates entities with snapRadius > 0.
        deallocator.components.set(
            CurseStateComponent(curseType: .memoryLeak, snapRadius: 0.0)
        )

        // RKFix 1: both components are REQUIRED for DragGesture().targetedToAnyEntity()
        // to hit-test this entity. Without them RealityKit silently ignores all touches.
        deallocator.components.set(InputTargetComponent())
        deallocator.components.set(
            CollisionComponent(shapes: [.generateSphere(radius: 0.025)])
        )

        root.addChild(ram)
        root.addChild(deallocator)
        return root
    }
}
