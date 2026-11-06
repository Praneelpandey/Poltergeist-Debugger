import RealityKit

// MARK: - SimulatorFallback

/// Provides an AnchorEntity(world: .zero) when ARWorldTrackingConfiguration
/// is not supported on the current device — most commonly the Xcode Simulator.
///
/// ## Design decision (Req 2.5, Steering §3.7)
/// A single runtime check (ARWorldTrackingConfiguration.isSupported) is the
/// only branch point between the device AR path and this path. We do NOT use
/// #if targetEnvironment(simulator) because that creates two divergent code
/// paths that never share test coverage. The runtime check keeps one unified
/// path that both branches exercise.
///
/// ## What this enables
/// All three puzzles, the ECS systems, CoreHaptics, and spatial audio work
/// without modification in the Simulator. Only ARKit plane detection is absent.
enum SimulatorFallback {

    /// Creates a world-origin anchor that acts as the Motherboard's parent
    /// when ARWorldTrackingConfiguration is unavailable.
    ///
    /// The Motherboard entity is added as a child of this anchor in ContentView,
    /// so puzzle layout relative to the Motherboard is identical to the device path.
    static func makeWorldAnchor() -> AnchorEntity {
        AnchorEntity(world: .zero)
    }
}
