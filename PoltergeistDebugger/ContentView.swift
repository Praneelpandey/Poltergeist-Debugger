import SwiftUI
import RealityKit
import ARKit

// MARK: - ContentView

/// Root SwiftUI scene. Owns the RealityView, HUD overlay, and all lifecycle
/// wiring (AR session, gestures, persistence, scene phase).
///
/// ## AR setup strategy (Task 2.4, Req 2.5)
/// content.session does NOT exist on RealityViewCameraContent on iOS.
/// We use AnchorEntity(.plane(...)) with a minimumBounds that satisfies the
/// ≥ 0.09 m² requirement (0.3 × 0.3 = 0.09), and subscribe to
/// SceneEvents.AnchoredStateChanged to detect plane acquisition (Req 1.7).
/// On Simulator, AnchorEntity(world: .zero) is used as a drop-in replacement.
struct ContentView: View {

    @State private var gameLoopState    = GameLoopState()
    @State private var isTrackingInterrupted = false
    @State private var showSaveError    = false

    // DragHandler owns gesture-to-entity translation (Task 7.1).
    @State private var dragHandler      = DragHandler()

    @Environment(\.scenePhase) private var scenePhase

    // Held alive so the AnchoredStateChanged subscription stays active.
    @State private var anchorSubscription: EventSubscription? = nil

    var body: some View {
        ZStack {
            arView
            HUDView(gameLoopState: gameLoopState,
                    isTrackingInterrupted: isTrackingInterrupted)
        }
        .ignoresSafeArea()
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your progress could not be saved. Previous save is intact.")
        }
    }

    // MARK: - RealityView + gestures

    private var arView: some View {
        RealityView { content in
            // make: runs once (background task → applied on @MainActor).

            let motherboard = PuzzleFactory.makeMotherboard()

            if ARWorldTrackingConfiguration.isSupported {
                // Device: wait for a horizontal plane ≥ 0.3 × 0.3 m (Req 1.2, 1.3).
                let planeAnchor = AnchorEntity(
                    .plane(.horizontal,
                           classification: .any,
                           minimumBounds: SIMD2<Float>(0.3, 0.3))
                )
                planeAnchor.addChild(motherboard)
                content.add(planeAnchor)

                // Subscribe to plane acquisition / loss (Req 1.7, 1.8).
                anchorSubscription = content.subscribe(
                    to: SceneEvents.AnchoredStateChanged.self,
                    on: planeAnchor
                ) { event in
                    if event.isAnchored {
                        isTrackingInterrupted = false
                        if gameLoopState.sessionPhase == .scanning {
                            gameLoopState.sessionPhase = .playing
                        }
                    } else {
                        if gameLoopState.sessionPhase == .playing ||
                           gameLoopState.sessionPhase == .victory {
                            isTrackingInterrupted = true
                        }
                    }
                }

            } else {
                // Simulator / no ARKit: world-origin anchor (Req 2.5).
                let worldAnchor = SimulatorFallback.makeWorldAnchor()
                worldAnchor.addChild(motherboard)
                content.add(worldAnchor)
                gameLoopState.sessionPhase = .playing
            }

        } update: { _ in
            // update: runs every frame on @MainActor.
            gameLoopState.processEvents()
        }
        // ── Gesture wiring (Task 7.2, Req 4.1, 4.2, Steering §4) ────────
        // Gestures are attached to the RealityView directly, not a parent
        // container. targetedToAnyEntity() hit-tests against all entities
        // that have InputTargetComponent + CollisionComponent.
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    dragHandler.handleChanged(value)
                }
                .onEnded { value in
                    dragHandler.handleEnded(value)
                }
        )
        .gesture(
            // SpatialTapGesture for future tap-to-select interactions (Req 4.2).
            // Phase 2 leaves the handler empty; Phase 3 wires puzzle-specific tap logic.
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { _ in
                    // Phase 3: handle tap-to-select for non-draggable interactions.
                }
        )
    }

    // MARK: - Scene phase lifecycle (persistence)

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {

        case .background:
            // Snapshot and save within 2 s of backgrounding (Req 11.1).
            let snapshot = PersistedGameState(
                from: gameLoopState,
                entitySnapshots: [:]   // Phase 2+: collect real transform snapshots
            )
            Task {
                do {
                    try await GameStatePersistence.shared.save(snapshot)
                } catch {
                    await MainActor.run { showSaveError = true }
                }
            }

        case .active:
            // Restore before first frame (Req 11.2).
            Task {
                if let saved = await GameStatePersistence.shared.load() {
                    await GameStatePersistence.restore(saved, into: gameLoopState)
                }
            }

        default:
            break
        }
    }
}

#Preview {
    ContentView()
}
