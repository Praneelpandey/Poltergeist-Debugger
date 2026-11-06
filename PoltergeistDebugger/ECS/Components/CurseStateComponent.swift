import RealityKit

// MARK: - CurseType

/// Identifies which of the three puzzles a given entity belongs to.
/// Used by CurseResolutionSystem to match Fix Entities against their correct Cursed Entity targets.
enum CurseType: String, Codable, CaseIterable, Sendable {
    case memoryLeak      = "memoryLeak"
    case raceCondition   = "raceCondition"
    case danglingPointer = "danglingPointer"
}

// MARK: - CurseStateComponent

/// Attached to every Cursed Entity (RAM bank, gear pair anchor, DanglingPointerAnchor).
///
/// This component is pure data — no methods, no SwiftUI references, no side effects.
/// All mutation is performed by CurseResolutionSystem in its per-frame update(context:).
///
/// Codable conformance is safe here because all stored properties
/// (Bool, CurseType, Float) are natively Codable.
struct CurseStateComponent: Component, Codable {

    /// True while the curse is unresolved. Set to false by CurseResolutionSystem.
    var isCursed: Bool

    /// Identifies which puzzle this entity belongs to.
    var curseType: CurseType

    /// World-space radius (metres) within which a matching Fix Entity triggers
    /// curse resolution. Defaults to 0.12 m (Req 3.1).
    ///
    /// Fix Entities carry this component as a type-tag only and use snapRadius: 0.0
    /// so they are never evaluated as resolution targets by CurseResolutionSystem.
    var snapRadius: Float

    init(curseType: CurseType, snapRadius: Float = 0.12) {
        self.isCursed   = true
        self.curseType  = curseType
        self.snapRadius = snapRadius
    }
}
