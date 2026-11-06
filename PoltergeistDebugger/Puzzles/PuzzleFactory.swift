import RealityKit

// MARK: - PuzzleFactory (stub)
//
// Full implementation: Tasks 8.1, 10.1, 11.1 (Phases 2 & 3).
// This stub provides makeMotherboard() so ContentView.swift has no
// unresolved-symbol errors during Phase 1.
enum PuzzleFactory {

    /// Creates the root Motherboard entity.
    /// Phase 2 adds child puzzle sub-trees via addChild() calls here.
    static func makeMotherboard() -> Entity {
        let root = Entity()
        root.name = "Motherboard"
        return root
    }
}
