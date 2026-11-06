import RealityKit

// MARK: - DragReturnSystem (stub)
//
// Full implementation: Task 6.3 (Phase 2).
// This stub exists solely so PoltergeistDebuggerApp.swift can call
// DragReturnSystem.registerSystem() without unresolved-symbol errors.
final class DragReturnSystem: System {

    private static let draggableQuery = EntityQuery(where: .has(DraggableComponent.self))

    required init(scene: Scene) {
        // Registration is performed in PoltergeistDebuggerApp.init() — not here.
    }

    func update(context: SceneUpdateContext) {
        // Ease-out return animation implemented in Task 6.3.
    }
}
