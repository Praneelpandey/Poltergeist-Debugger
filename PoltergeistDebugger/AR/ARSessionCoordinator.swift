import ARKit
import RealityKit

// MARK: - ARSessionCoordinator

/// Modular ARKit delegate that owns plane-selection logic.
///
/// ## Responsibilities
/// - Tracks all detected ARPlaneAnchors reported by ARKit.
/// - Exposes selectBestPlane(from:) as a pure static function so it can be
///   property-tested without a live AR session (Property 11).
/// - Reports tracking-interruption events so ContentView can show the
///   recovery indicator (Req 1.8) without coupling to SwiftUI.
///
/// ## What it does NOT do
/// - It does NOT run ARSession directly. ContentView drives the session via
///   AnchorEntity(.plane(...)) inside RealityView; this coordinator handles
///   the delegate callbacks that flow from that session.
/// - It does NOT reference GameLoopState. Phase transitions are communicated
///   via the onMotherboardAnchored and onTrackingInterrupted closures so
///   this type stays free of SwiftUI/Observation imports.
final class ARSessionCoordinator: NSObject, ARSessionDelegate {

    // MARK: - Callbacks (set by ContentView)

    /// Called once when a suitable plane has been found and the Motherboard
    /// has been anchored. Receives the chosen plane anchor.
    var onMotherboardAnchored: ((ARPlaneAnchor) -> Void)?

    /// Called when ARKit tracking is interrupted after anchoring (Req 1.8).
    var onTrackingInterrupted: (() -> Void)?

    /// Called when ARKit tracking resumes after interruption (Req 1.8).
    var onTrackingResumed: (() -> Void)?

    // MARK: - Internal state

    private var detectedPlanes: [UUID: ARPlaneAnchor] = [:]
    private var motherboardAnchored = false

    // MARK: - ARSessionDelegate — plane lifecycle

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for case let plane as ARPlaneAnchor in anchors {
            detectedPlanes[plane.identifier] = plane
        }
        evaluatePlanes()
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for case let plane as ARPlaneAnchor in anchors {
            detectedPlanes[plane.identifier] = plane
        }
        evaluatePlanes()
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            detectedPlanes.removeValue(forKey: anchor.identifier)
        }
    }

    // MARK: - ARSessionDelegate — tracking state

    func sessionWasInterrupted(_ session: ARSession) {
        onTrackingInterrupted?()
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        onTrackingResumed?()
    }

    // MARK: - Plane selection

    /// Choose the best plane from all currently detected planes.
    ///
    /// Selects the plane with the largest surface area that meets the minimum
    /// bound of 0.09 m² (Req 1.3, 1.4). Pure function — no side effects —
    /// so it is directly callable from property tests (Property 11).
    ///
    /// - Parameter planes: Collection of ARPlaneAnchors to evaluate.
    /// - Returns: The anchor with the largest area ≥ 0.09 m², or nil if none qualify.
    static func selectBestPlane(from planes: [ARPlaneAnchor]) -> ARPlaneAnchor? {
        planes
            .filter { $0.planeExtent.width * $0.planeExtent.height >= 0.09 }
            .max(by: { $0.planeExtent.width * $0.planeExtent.height
                     < $1.planeExtent.width * $1.planeExtent.height })
    }

    // MARK: - Private

    private func evaluatePlanes() {
        guard !motherboardAnchored else { return }
        guard let best = ARSessionCoordinator.selectBestPlane(
            from: Array(detectedPlanes.values)
        ) else { return }

        motherboardAnchored = true
        onMotherboardAnchored?(best)
    }
}
