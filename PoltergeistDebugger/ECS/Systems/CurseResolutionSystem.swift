import RealityKit

// MARK: - CurseResolutionSystem (stub)
//
// Full implementation: Task 6.1 (Phase 2).
// This stub exists solely so PoltergeistDebuggerApp.swift can call
// CurseResolutionSystem.registerSystem() without unresolved-symbol errors.
//
// Threading contract: update(context:) is NOT @MainActor-isolated.
// Never call registerSystem() from inside this init — see App entry point.
final class CurseResolutionSystem: System {

    private static let cursedQuery = EntityQuery(where: .has(CurseStateComponent.self))
    private static let fixQuery    = EntityQuery(where: .has(DraggableComponent.self))

    required init(scene: Scene) {
        // Registration is performed in PoltergeistDebuggerApp.init() — not here.
    }

    func update(context: SceneUpdateContext) {
        // Full proximity-detection logic implemented in Task 6.1.
    }
}
