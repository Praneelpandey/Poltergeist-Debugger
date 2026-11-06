# Implementation Plan: Poltergeist Debugger

## Overview

Implementation is divided into four phased milestones that build on each other without orphaned code:

- **Phase 1 — Spatial Anchor & Base UI**: project skeleton, ECS registration, AR session, simulator fallback, base HUD, persistence infrastructure.
- **Phase 2 — The Memory Leak**: first complete puzzle end-to-end (RAM bank, Deallocator, particles, haptics, audio, HUD increment).
- **Phase 3 — The Race Condition & Dangling Pointer**: two remaining puzzles, gear physics, drift animation, `setParent()` snap, occupied-zone rejection.
- **Phase 4 — Haunting Polish**: CoreHaptics engine, spatial audio coordinator, Metal HUD shader, victory overlay, full game-loop win condition, save/restore persistence.

Every task names the exact file(s) to create or modify and references the requirement(s) it satisfies. The five RealityKit bug fixes from the design are embedded as explicit steps (tagged **[RKFix N]**). Property-based tests follow immediately after the code they validate.

---

## Tasks

### Phase 1 — Spatial Anchor & Base UI

- [ ] 1. Scaffold project structure and register ECS types
  - [ ] 1.1 Create `PoltergeistDebuggerApp.swift` — `@main` entry point that calls `CurseStateComponent.registerComponent()`, `DraggableComponent.registerComponent()`, `CurseResolutionSystem.registerSystem()`, `DragReturnSystem.registerSystem()` in `App.init()` before any `RealityView` is instantiated.
    - **[RKFix 4]** Registration must happen in `App.init()`, not inside `System.init(scene:)`, to prevent a recursive cycle.
    - _Requirements: 3.3_
  - [ ] 1.2 Create `ECS/Components/CurseStateComponent.swift` — define `CurseType` enum and `CurseStateComponent` struct conforming to `RealityKit.Component` and `Codable` with `isCursed: Bool`, `curseType: CurseType`, `snapRadius: Float` defaulting to `0.12`.
    - _Requirements: 3.1_
  - [ ] 1.3 Create `ECS/Components/DraggableComponent.swift` — define `DraggableComponent` conforming to `RealityKit.Component` with `restPosition: SIMD3<Float>`, `isDragging: Bool`, `originalBrightness: Float`.
    - _Requirements: 3.2_
  - [ ] 1.4 Create `State/SessionPhase.swift` — define `SessionPhase` enum (`scanning`, `playing`, `victory`) conforming to `String`, `Codable`, `Sendable`.
    - _Requirements: 1.7, 10.3_
  - [ ] 1.5 Create `State/CurseEventBuffer.swift` — `NSLock`-protected FIFO queue with `post(_:)` and `drainEvents()` methods; expose `CurseEventBuffer.shared` singleton.
    - _Requirements: 3.6, 3.7_
  - [ ]* 1.6 Write property test for `CurseEventBuffer` — Property 4: event buffer completeness under concurrency.
    - **Property 4: Event Buffer Completeness Under Concurrency**
    - Concurrently post N events from multiple `DispatchQueue.global()` threads, then call `drainEvents()` once and assert count equals N; second drain must return empty.
    - **Validates: Requirements 3.5, 3.7**
  - [ ] 1.7 Create `State/GameLoopState.swift` — `@Observable @MainActor` class with `sessionPhase`, `resolvedCount`, `activeCurses`, `processEvents()`, `handleResolution(of:)`, and `restartSession()`.
    - _Requirements: 1.7, 10.1, 10.2, 10.3, 10.6, 10.7_
  - [ ]* 1.8 Write property tests for `GameLoopState` — Properties 5 & 6: `resolvedCount` bounded/monotonic and victory entered exactly on third resolution.
    - **Property 5: Resolved Count Bounded and Monotonic**
    - Feed arbitrary sequences of `CurseType` resolution events and assert count never decreases and never exceeds 3.
    - **Validates: Requirements 10.1, 10.7**
    - **Property 6: Victory Entered Exactly When resolvedCount Reaches 3**
    - Permute all three curse types; assert `.victory` only after the third distinct type, and extra events leave phase unchanged.
    - **Validates: Requirements 10.3, 10.7**
  - [ ]* 1.9 Write property test for restart — Property 10: restart round-trips to clean playing state.
    - **Property 10: Restart Round-Trips to Clean Playing State**
    - Drive a `GameLoopState` to `.victory` with any resolution order, call `restartSession()`, assert `resolvedCount == 0`, `activeCurses == CurseType.allCases`, `sessionPhase == .playing`.
    - **Validates: Requirements 10.6**

- [ ] 2. AR session and plane detection
  - [ ] 2.1 Create `AR/ARSessionCoordinator.swift` — `ARSessionDelegate` that maintains `detectedPlanes`, exposes `selectBestPlane(from:)` static helper, anchors the Motherboard to the largest plane ≥ 0.09 m², transitions `GameLoopState.sessionPhase` to `.playing`, shows recovery indicator on tracking interruption.
    - _Requirements: 1.2, 1.3, 1.4, 1.7, 1.8_
  - [ ]* 2.2 Write property test for plane selection — Property 11: largest-area plane is always selected.
    - **Property 11: Largest-Area Plane Is Always Selected for Anchoring**
    - Generate arbitrary arrays of `MockARPlaneAnchor` with distinct areas ≥ 0.09 m²; assert `selectBestPlane(from:)` always returns the one with maximum area.
    - **Validates: Requirements 1.4**
  - [ ] 2.3 Create `AR/SimulatorFallback.swift` — returns an `AnchorEntity(world: .zero)` when `ARWorldTrackingConfiguration.isSupported` is `false`; no `#if targetEnvironment(simulator)` preprocessor guard.
    - _Requirements: 2.5_
  - [ ] 2.4 Create `ContentView.swift` — root SwiftUI scene containing a `RealityView` whose `make:` closure branches on `ARWorldTrackingConfiguration.isSupported`, runs `ARWorldTrackingConfiguration` with `.horizontal` plane detection on device, uses `AnchorEntity(world: .zero)` on Simulator; `update:` closure calls `gameLoopState.processEvents()` each frame.
    - _Requirements: 1.1, 1.2, 2.1, 2.5_

- [ ] 3. Base HUD and scanning overlay
  - [ ] 3.1 Create `HUD/ScanningView.swift` — SwiftUI view displayed while `sessionPhase == .scanning`, showing a scanning indicator instructing the player to point the device at a flat surface.
    - _Requirements: 1.5_
  - [ ] 3.2 Create `HUD/HUDView.swift` — SwiftUI overlay composited on top of `RealityView`; shows `resolvedCount/3`, lists names of all curses with `isCursed == true`; conditionally shows `ScanningView` when scanning, `VictoryOverlayView` (stub) when victory; must update within 16 ms of any `GameLoopState` publish.
    - _Requirements: 2.2, 2.4, 10.2_
  - [ ] 3.3 Create `HUD/VictoryOverlayView.swift` — stub SwiftUI view with the "All Bugs Exorcised" message and a clearly labeled restart button that calls `gameLoopState.restartSession()`; full styling deferred to Phase 4.
    - _Requirements: 10.5, 10.6_

- [ ] 4. Persistence infrastructure
  - [ ] 4.1 Create `Persistence/EntityTransformSnapshot.swift` — `Codable Equatable` struct flattening a `Transform` into scalar fields plus computed `position`/`rotation` properties.
    - _Requirements: 11.1_
  - [ ] 4.2 Create `Persistence/PersistedGameState.swift` — top-level `Codable Equatable` payload with `schemaVersion: Int` (current = 1), `resolvedPuzzles: [String: Bool]`, `entitySnapshots: [String: EntityTransformSnapshot]`, `sessionPhase: String`.
    - _Requirements: 11.1, 11.3, 11.5, 11.6_
  - [ ]* 4.3 Write property test for serialization round-trip — Property 1.
    - **Property 1: Serialization Round-Trip**
    - Generate arbitrary `PersistedGameState` values (all 8 resolved-puzzle combinations, random float transforms, all three session-phase raw values); encode then decode and assert structural equality.
    - **Validates: Requirements 11.5, 11.2**
  - [ ] 4.4 Create `Persistence/GameStatePersistence.swift` — Swift `actor` with `save(_:)` (atomic write, throws on failure) and `load()` (returns `nil` and deletes file on schema mismatch or malformed JSON); file path fixed at `Documents/poltergeist_save.json`.
    - _Requirements: 11.2, 11.3, 11.4, 11.6, 11.7_
  - [ ] 4.5 Wire `GameStatePersistence` into `ContentView.swift` — call `save` on `.background` scene-phase transition within 2 s, call `load` and restore `GameLoopState` on `.active` before first frame.
    - _Requirements: 11.1, 11.2_

- [ ] 5. Checkpoint — Phase 1 complete
  - Ensure all tests pass and the app builds for both Simulator (world-origin anchor) and a real device (plane detection path). Ask the user if questions arise.

---

### Phase 2 — The Memory Leak Puzzle

- [ ] 6. ECS systems skeleton
  - [ ] 6.1 Create `ECS/Systems/CurseResolutionSystem.swift` — `RealityKit.System` with `update(context:)` that queries cursed entities and fix entities, computes world-space distance, sets `isCursed = false` when `dist ≤ snapRadius`, posts exactly one `CurseResolvedEvent` per resolved curse type via `CurseEventBuffer.shared`; guards `fix.entity.id != cursedEntity.id` to prevent self-resolution.
    - **[RKFix 3]** Self-resolution guard: the Dangling Pointer drifter carries a type-tag `CurseStateComponent` with `snapRadius 0.0`; only the `DanglingPointerAnchor` on the Motherboard is the resolution target.
    - _Requirements: 3.3, 3.4, 3.5, 3.6, 3.7_
  - [ ]* 6.2 Write property tests for `CurseResolutionSystem` — Properties 2, 3, & 7.
    - **Property 2: Snap Triggers Resolution**
    - For arbitrary `snapRadius` and fix distance ≤ `snapRadius`, assert `isCursed == false` after one system frame.
    - **Validates: Requirements 3.4, 4.5, 5.3, 6.3, 7.3**
    - **Property 3: Out-of-Radius Leaves Curse Unchanged**
    - For arbitrary `snapRadius` and fix distance strictly > `snapRadius`, assert `isCursed == true` after one system frame.
    - **Validates: Requirements 5.5, 7.7**
    - **Property 7: Wrong-Type Fix Entity Leaves Curse Unchanged**
    - For any curse type T and a fix entity of type T′ ≠ T at any distance (including inside `snapRadius`), assert `isCursed == true` after one system frame.
    - **Validates: Requirements 5.4**
  - [ ] 6.3 Create `ECS/Systems/DragReturnSystem.swift` — `RealityKit.System` that detects `isDragging == false` on a `DraggableComponent` whose world position differs from `restPosition`, and drives a `FromToByAnimation` with an ease-out curve over 0.2–0.5 s back to `restPosition`.
    - _Requirements: 4.6, 4.7_

- [ ] 7. Spatial drag gesture handler
  - [ ] 7.1 Create `Gestures/DragHandler.swift` — `@MainActor` class implementing `handleChanged(_:)` (sets `isDragging = true` on first call, applies 1.3× brightness boost, fires pickup haptic, updates world-space position from `value.convert(_:from:to:)` each frame) and `handleEnded(_:)` (clears `isDragging`, removes brightness boost; `DragReturnSystem` drives the return animation).
    - **[RKFix 2]** The `isDragging` flag must NOT short-circuit the position update; position update runs on every `onChanged` callback, guard is only for the one-time setup.
    - _Requirements: 4.1, 4.4, 4.6, 4.7_
  - [ ] 7.2 Wire `DragGesture().targetedToAnyEntity()` and `SpatialTapGesture().targetedToAnyEntity()` gesture modifiers into `ContentView.swift` `RealityView`, delegating to `DragHandler`.
    - _Requirements: 4.1, 4.2, 4.3_

- [ ] 8. Memory Leak puzzle entity factory
  - [ ] 8.1 Create `Puzzles/PuzzleFactory.swift` with `makeMotherboard()` and `makeMemoryLeakPuzzle()` — RAM bank entity with `CurseStateComponent(.memoryLeak)` and green `ParticleEmitterComponent`; Deallocator fix entity with `DraggableComponent`, type-tag `CurseStateComponent(.memoryLeak, snapRadius: 0.0)`.
    - **[RKFix 1]** Attach `InputTargetComponent` and `CollisionComponent` (sphere shape) to the Deallocator so `DragGesture().targetedToAnyEntity()` can hit-test it. Without these two components RealityKit ignores the entity entirely.
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_
  - [ ] 8.2 Create `Puzzles/MemoryLeakPuzzle.swift` — `syncParticleEmitter(on:)` helper that sets `ParticleEmitterComponent.isEmitting` to match `CurseStateComponent.isCursed`; wires up resolution callback (halt particles, play success sound) when `GameLoopState` receives `.memoryLeak` resolution event.
    - _Requirements: 5.1, 5.2, 5.6, 5.7_
  - [ ]* 8.3 Write property test for particle emitter state — Property 8.
    - **Property 8: Particle Emitter Active While Cursed**
    - For arbitrary `isCursed` bool values, set `CurseStateComponent.isCursed` on the RAM bank entity, call `MemoryLeakPuzzle.syncParticleEmitter(on:)`, assert `ParticleEmitterComponent.isEmitting == isCursed`.
    - **Validates: Requirements 5.2, 6.2**

- [ ] 9. Checkpoint — Phase 2 complete
  - Ensure Memory Leak puzzle resolves end-to-end: drag Deallocator into snap zone, particles stop, HUD count increments to 1. All tests pass. Ask the user if questions arise.

---

### Phase 3 — Race Condition & Dangling Pointer Puzzles

- [ ] 10. Race Condition puzzle
  - [ ] 10.1 Add `makeRaceConditionPuzzle()` to `Puzzles/PuzzleFactory.swift` — two gear entities with `PhysicsMotionComponent` angular velocities 3.0 and 7.0 rad/s, spark `ParticleEmitterComponent`, `CurseStateComponent(.raceCondition)`; Mutex Lock fix entity with `DraggableComponent` and type-tag `CurseStateComponent(.raceCondition, snapRadius: 0.0)`.
    - **[RKFix 1]** Attach `InputTargetComponent` and `CollisionComponent` (box shape) to the Mutex Lock fix entity.
    - **[RKFix 5]** Attach `PhysicsBodyComponent(mode: .kinematic)` to each gear entity — without it `PhysicsMotionComponent` renders the mesh but does not rotate it.
    - _Requirements: 6.1, 6.2_
  - [ ] 10.2 Create `Puzzles/RaceConditionPuzzle.swift` — resolution handler that sets both gear `PhysicsMotionComponent.angularVelocity` to `SIMD3(0, 5.0, 0)`, disables spark `ParticleEmitterComponent.isEmitting` on both gears, increments `GameLoopState.resolvedCount`.
    - _Requirements: 6.3, 6.4, 6.5, 6.6_

- [ ] 11. Dangling Pointer puzzle
  - [ ] 11.1 Add `makeDanglingPointerPuzzle()` to `Puzzles/PuzzleFactory.swift` — `DanglingPointerAnchor` entity on the Motherboard with `CurseStateComponent(.danglingPointer, snapRadius: 0.12)` as the resolution target; detached `DanglingPointer` drifter `ModelEntity` added at world level with `DraggableComponent` and type-tag `CurseStateComponent(.danglingPointer, snapRadius: 0.0)`.
    - **[RKFix 1]** Attach `InputTargetComponent` and `CollisionComponent` (box shape) to the drifter.
    - **[RKFix 3]** Drifter `snapRadius` must be `0.0` so `CurseResolutionSystem` never evaluates it as a resolution target, preventing self-collision auto-resolve on frame 1.
    - _Requirements: 7.1, 7.2_
  - [ ] 11.2 Create `Puzzles/DanglingPointerPuzzle.swift` — applies a continuous drift `Transform` animation (translation speed ≤ 0.05 m/s) to the drifter; resolution handler calls `setParent()` to attach drifter to Motherboard, interpolates local position to anchor offset over 0.2 s, sets `CurseStateComponent.isCursed = false`, increments `resolvedCount`; if released outside `snapRadius` restores drifting with `isCursed = true`.
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7_

- [ ] 12. Snap-zone occupancy rejection
  - [ ] 12.1 Extend `CurseResolutionSystem.swift` — track occupied snap zones in a `Set<EntityID>`; when a second fix entity enters an already-occupied zone, skip resolution, fire a haptic rejection pulse via `HapticEngine.shared`, and let `DragReturnSystem` return the entity to rest.
    - _Requirements: 4.8_

- [ ] 13. Checkpoint — Phase 3 complete
  - All three puzzles resolve independently. HUD count cycles 0→1→2→3, triggering `.victory`. Restart resets all puzzles. All property tests pass. Ask the user if questions arise.

---

### Phase 4 — Haunting Polish

- [ ] 14. CoreHaptics engine
  - [ ] 14.1 Create `Haptics/HapticEngine.swift` — `@MainActor` singleton wrapping `CHHapticEngine`; `start()` / `stop()` lifecycle (called on `scenePhase` `.active` / `.background`); `playSnap()` (intensity 0.9, duration 0.10 s); `playPickup()` (intensity 0.3, duration 0.07 s); `playVictory()` (3 beats at spacing 0.12 s, intensity 0.85, parameter curve varying ≥ 0.3 units); silent failure path when engine unavailable.
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_
  - [ ]* 14.2 Write property test for victory haptic — Property 9.
    - **Property 9: Victory Haptic Contains Exactly Three Beats**
    - Call `HapticEngine.makeVictoryPattern()` N times; for each result assert exactly 3 `CHHapticEvent` instances, each intensity in 0.6–1.0, adjacent beats separated by 0.10–0.15 s.
    - **Validates: Requirements 8.4**
  - [ ] 14.3 Wire `HapticEngine.shared.start()` / `stop()` into `ContentView.swift` `onChange(of: scenePhase)`.
    - _Requirements: 8.1_
  - [ ] 14.4 Connect haptic calls throughout gesture and resolution code — `playPickup()` in `DragHandler.handleChanged` on first drag frame; `playSnap()` within 50 ms of snap completion in `CurseResolutionSystem`; `playVictory()` on `.victory` entry in `GameLoopState`.
    - _Requirements: 4.5, 8.2, 8.3, 8.4_

- [ ] 15. Spatial audio
  - [ ] 15.1 Create `Audio/SpatialAudioCoordinator.swift` — loads background ambiance `AudioFileResource`, attaches it as looping audio to the Motherboard entity on session start; loads per-puzzle looping positional cues attached to each cursed entity; plays non-looping resolution sound effect and stops the looping cue on puzzle resolution; configures attenuation (reference distance ≤ 0.5 m, max audible ≤ 5 m); silent fallback on load failure.
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_
  - [ ] 15.2 Wire `SpatialAudioCoordinator` into `ContentView.swift` — start ambient audio when Motherboard anchor is established; start cursed-entity audio when `GameLoopState` enters `.playing`.
    - _Requirements: 9.1, 9.2_

- [ ] 16. Metal HUD shader
  - [ ] 16.1 Create `HUD/Shaders/PoltergeistHUD.metal` — `[[stitchable]] half4 poltergeistHUD(float2 position, SwiftUI::Layer layer, float2 size, float time)` implementing desaturation (NTSC weights), radial vignette (`smoothstep(0.4, 1.2, dist²)`), and animated film grain (sine-hash noise driven by `time`).
    - _Requirements: 2.3_
  - [ ] 16.2 Apply `.layerEffect(ShaderLibrary.poltergeistHUD(...), maxSampleOffset: .zero)` in `HUDView.swift`, driven by `TimelineView(.animation)` for per-frame `elapsedTime`.
    - _Requirements: 2.3_

- [ ] 17. Victory overlay polish and win condition wiring
  - [ ] 17.1 Style `HUD/VictoryOverlayView.swift` to full-screen overlay covering all gameplay elements; display "All Bugs Exorcised" message and restart button; trigger `playVictory()` haptic and victory audio sting (≤ 5 s) on entry; handle missing audio asset gracefully.
    - _Requirements: 10.4, 10.5, 10.8_
  - [ ] 17.2 Verify `GameLoopState.sessionPhase` transitions to `.victory` within 1 s of third puzzle resolving and that `restartSession()` resets all `CurseStateComponent` instances to `isCursed = true`, re-initialises puzzle entities, and returns `sessionPhase` to `.playing` without app relaunch.
    - _Requirements: 10.3, 10.6_

- [ ] 18. Permission and error-state screens
  - [ ] 18.1 Add camera-permission request at launch in `ContentView.swift`; show non-AR fallback screen with deep link to iOS Settings when permission is denied.
    - _Requirements: 1.1, 1.6_

- [ ] 19. Final checkpoint — all phases complete
  - All 11 property tests pass, all unit tests pass, app builds for Simulator and device. Full game loop: anchor → three puzzles → victory overlay → restart. Ask the user if questions arise.

---

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP.
- Each task references specific requirements for traceability.
- The five **[RKFix N]** tags correspond to the five known RealityKit integration pitfalls called out in the design document.
- Property tests use **swift-testing** + **swift-check** (Xcode 16+); each test runs a minimum of 100 iterations.
- All property tests are annotated `// Feature: poltergeist-debugger, Property N: <text>` as specified in the design.
- Checkpoints ensure incremental validation at each phase boundary.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.2", "1.3", "1.4"] },
    { "id": 1, "tasks": ["1.5", "4.1", "4.2"] },
    { "id": 2, "tasks": ["1.6", "1.7", "4.3"] },
    { "id": 3, "tasks": ["1.8", "1.9", "4.4"] },
    { "id": 4, "tasks": ["1.1", "2.3", "4.5"] },
    { "id": 5, "tasks": ["2.1", "2.4"] },
    { "id": 6, "tasks": ["2.2", "3.1"] },
    { "id": 7, "tasks": ["3.2", "3.3"] },
    { "id": 8, "tasks": ["6.1", "6.3"] },
    { "id": 9, "tasks": ["6.2", "7.1"] },
    { "id": 10, "tasks": ["7.2", "8.1"] },
    { "id": 11, "tasks": ["8.2", "10.1"] },
    { "id": 12, "tasks": ["8.3", "11.1", "12.1"] },
    { "id": 13, "tasks": ["10.2", "11.2"] },
    { "id": 14, "tasks": ["14.1", "15.1"] },
    { "id": 15, "tasks": ["14.2", "14.3", "15.2", "16.1"] },
    { "id": 16, "tasks": ["14.4", "16.2", "17.1"] },
    { "id": 17, "tasks": ["17.2", "18.1"] }
  ]
}
```
