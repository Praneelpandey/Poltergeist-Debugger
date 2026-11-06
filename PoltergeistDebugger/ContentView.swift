import SwiftUI
import RealityKit
import ARKit

// MARK: - ContentView

/// Root SwiftUI scene. Owns the RealityView, HUD overlay, and all
/// lifecycle wiring (AR session, persistence, scene phase).
///
/// ## AR setup strategy (Task 2.4, Req 2.5)
/// We do NOT access content.session inside RealityView — that property does
/// not exist on RealityViewCameraContent on iOS. Instead:
///
/// On device (ARWorldTrackingConfiguration.isSupported == true):
///   AnchorEntity(.plane(.horizontal, classification: .any,
///                       minimumBounds: SIMD2(0.3, 0.3)))
///   This tells RealityKit to wait for a real horizontal plane ≥ 0.3×0.3 m
///   (~0.09 m²) before making the anchor active (Req 1.3).
///   We subscribe to SceneEvents.AnchoredStateChanged to detect the moment
///   the anchor becomes active and transition sessionPhase → .playing (Req 1.7).
///
/// On Simulator (isSupported == false):
///   AnchorEntity(world: .zero) — immediate placement, no plane scan needed.
///   sessionPhase is set to .playing in the make: closure directly.
struct ContentView: View {

    // Shared observable state — injected into HUDView and RealityView update:.
    @State private var gameLoopState = GameLoopState()

    // Tracks ARKit tracking interruption for the HUD recovery banner (Req 1.8).
    @State private var isTrackingInterrupted = false

    // Save-failure flag — surfaced to player within 3 s (Req 11.7).
    @State private var showSaveError = false

    @Environment(\.scenePhase) private var scenePhase

    // EventSubscription must be held alive for the subscription to remain active.
    @State private var anchorSubscription: EventSubscription? = nil

    // The ARSessionCoordinator stays alive for the session lifetime.
    @State private var arCoordinator = ARSessionCoordinator()

    var body: some View {
        ZStack {
            arView
            HUDView(gameLoopState: gameLoopState,
                    isTrackingInterrupted: isTrackingInterrupted)
        }
        .ignoresSafeArea()
        // Save on background (Req 11.1)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
        // Save-failure alert (Req 11.7)
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your progress could not be saved. Previous save is intact.")
        }
    }

    // MARK: - RealityView

    private var arView: some View {
        RealityView { content in
            // ── make: runs once on a background task, then the result is
            //    applied to the scene on @MainActor. ──────────────────────

            let motherboard = PuzzleFactory.makeMotherboard()

            if ARWorldTrackingConfiguration.isSupported {
                // Device path: use a plane-detection anchor (Req 1.2, 1.3).
                // minimumBounds SIMD2(0.3, 0.3) means RealityKit waits for a
                // plane at least 0.3 m × 0.3 m before activating this anchor,
                // satisfying the ≥ 0.09 m² requirement (0.3 × 0.3 = 0.09 m²).
                let planeAnchor = AnchorEntity(
                    .plane(.horizontal,
                           classification: .any,
                           minimumBounds: SIMD2<Float>(0.3, 0.3))
                )
                planeAnchor.addChild(motherboard)
                content.add(planeAnchor)

                // Subscribe to anchor activation. When this anchor becomes
                // active it means a qualifying plane has been found and the
                // Motherboard is placed — transition to .playing (Req 1.7).
                // The subscription is stored in @State so it stays alive.
                anchorSubscription = content.subscribe(
                    to: SceneEvents.AnchoredStateChanged.self,
                    on: planeAnchor
                ) { [weak planeAnchor] event in
                    // This closure fires on @MainActor in RealityKit iOS 17+.
                    guard event.isAnchored else {
                        // Anchor lost after being established → interruption.
                        if gameLoopState.sessionPhase == .playing ||
                           gameLoopState.sessionPhase == .victory {
                            isTrackingInterrupted = true
                        }
                        return
                    }
                    // Anchor became active.
                    isTrackingInterrupted = false
                    if gameLoopState.sessionPhase == .scanning {
                        gameLoopState.sessionPhase = .playing
                    }
                }

            } else {
                // Simulator / unsupported device path (Req 2.5, Steering §3.7).
                let worldAnchor = SimulatorFallback.makeWorldAnchor()
                worldAnchor.addChild(motherboard)
                content.add(worldAnchor)

                // No plane detection needed — go straight to playing.
                gameLoopState.sessionPhase = .playing
            }

        } update: { _ in
            // ── update: runs every frame on @MainActor ───────────────────
            // Drain ECS events and update GameLoopState (Req 3.7).
            gameLoopState.processEvents()
        }
    }

    // MARK: - Scene phase lifecycle

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {

        case .background:
            // Save within 2 s of backgrounding (Req 11.1).
            // Entity transform snapshots are omitted in Phase 1 (no puzzle entities yet);
            // Phase 2+ will pass real snapshots here.
            let snapshot = PersistedGameState(
                from: gameLoopState,
                entitySnapshots: [:]
            )
            Task {
                do {
                    try await GameStatePersistence.shared.save(snapshot)
                } catch {
                    await MainActor.run { showSaveError = true }
                }
            }

        case .active:
            // Restore persisted state before the first frame (Req 11.2).
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
