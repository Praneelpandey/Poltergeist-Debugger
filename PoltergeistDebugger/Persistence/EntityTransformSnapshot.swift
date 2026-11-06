import Foundation
import RealityKit

// MARK: - EntityTransformSnapshot

/// Flattened, Codable representation of a RealityKit Transform.
///
/// RealityKit's Transform is not Codable, and simd_quatf stores its components
/// as a single SIMD4. We decompose to named scalar fields so JSON is readable
/// and schema-stable across versions.
///
/// Equatable conformance is required for Property 1 (round-trip test):
/// decode(encode(snapshot)) == snapshot.
struct EntityTransformSnapshot: Codable, Equatable {

    // Position
    var positionX: Float
    var positionY: Float
    var positionZ: Float

    // Rotation (unit quaternion stored as four scalars)
    // simd_quatf layout: .imag.x/.y/.z = imaginary part, .real = scalar part.
    var rotationX: Float   // imaginary i
    var rotationY: Float   // imaginary j
    var rotationZ: Float   // imaginary k
    var rotationW: Float   // real (scalar) part

    // Uniform scale (non-uniform scale is not used in this project)
    var scale: Float

    // MARK: Convenience — reconstruct RealityKit types

    var position: SIMD3<Float> {
        SIMD3(positionX, positionY, positionZ)
    }

    var rotation: simd_quatf {
        simd_quatf(ix: rotationX, iy: rotationY, iz: rotationZ, r: rotationW)
    }

    // MARK: Init from RealityKit Transform

    /// Snapshot the current transform of a RealityKit entity.
    init(transform: Transform) {
        positionX = transform.translation.x
        positionY = transform.translation.y
        positionZ = transform.translation.z
        rotationX = transform.rotation.imag.x
        rotationY = transform.rotation.imag.y
        rotationZ = transform.rotation.imag.z
        rotationW = transform.rotation.real
        scale     = transform.scale.x   // uniform scale assumed
    }

    // MARK: Memberwise init (used in tests)

    init(positionX: Float, positionY: Float, positionZ: Float,
         rotationX: Float, rotationY: Float, rotationZ: Float, rotationW: Float,
         scale: Float) {
        self.positionX = positionX; self.positionY = positionY; self.positionZ = positionZ
        self.rotationX = rotationX; self.rotationY = rotationY
        self.rotationZ = rotationZ; self.rotationW = rotationW
        self.scale     = scale
    }
}
