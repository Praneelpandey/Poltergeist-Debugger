import RealityKit

// MARK: - MemoryLeakPuzzle

/// Stateless helpers for the Memory Leak puzzle (Req 5.1–5.7).
///
/// All methods are static — this is a namespace, not a class instance,
/// because puzzle state lives entirely in RealityKit ECS components.
enum MemoryLeakPuzzle {

    // MARK: - Entity names (shared with PuzzleFactory and persistence)

    static let ramBankName    = "RAMBank"
    static let deallocatorName = "Deallocator"

    // MARK: - Particle emitter sync (RKFix-Phase2 #3)

    /// Synchronise the RAM bank's ParticleEmitterComponent with its curse state.
    ///
    /// Called by CurseResolutionSystem immediately when isCursed flips to false,
    /// so the green mist stops in the same frame the resolution fires.
    ///
    /// Also safe to call from a reset/restart path with isCursed = true
    /// to restart emission without rebuilding the entity.
    ///
    /// - Parameter entity: The RAM bank entity (must carry both
    ///   CurseStateComponent and ParticleEmitterComponent).
    static func syncParticleEmitter(on entity: Entity) {
        guard let curseState = entity.components[CurseStateComponent.self],
              var particles  = entity.components[ParticleEmitterComponent.self]
        else { return }

        particles.isEmitting = curseState.isCursed
        entity.components[ParticleEmitterComponent.self] = particles
    }

    // MARK: - Particle emitter factory

    /// Builds the green-mist ParticleEmitterComponent for the RAM bank.
    ///
    /// Kept here (rather than in PuzzleFactory) so MemoryLeakPuzzle owns all
    /// particle configuration for this puzzle — easy to tune in one place.
    static func makeGreenParticleEmitter() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        // Continuous emission: 200 particles/s gives a dense mist look.
        emitter.mainEmitter.birthRate = 200
        emitter.mainEmitter.color     = .constant(.single(.green))
        emitter.mainEmitter.lifeSpan  = 1.5
        emitter.mainEmitter.speed     = 0.05    // slow upward drift
        emitter.isEmitting            = true    // starts active (curse is active)
        return emitter
    }
}
