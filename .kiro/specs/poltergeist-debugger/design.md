# Design Document

## Overview

Poltergeist Debugger is an iOS 17+ Augmented Reality puzzle game built with SwiftUI and RealityKit. It materialises three classic software bugs—Memory Leak, Race Condition, and Dangling Pointer—as haunted 3D entities anchored to the player's real desk via ARKit plane detection. Players resolve each curse by physically dragging a matching Fix Entity into a Snap Zone, receiving CoreHaptics and spatial audio reinforcement at every interaction beat.

The architecture follows a strict separation of concerns:

- **RealityKit ECS** owns all per-frame simulation logic (components, systems).
- **SwiftUI + RealityView** owns all 2D rendering and gesture dispatch.
- **`GameLoopState`** is the single `@Observable` view model that bridges ECS events to SwiftUI state.
- **Persistence** is handled by a Swift `actor` that reads/writes a versioned Codable JSON file.

The design targets iPhone 12 and later (A14 Bionic, LiDAR optional) running iOS 17.0+.

---

## Architecture

### High-Level Layer Diagram

```mermaid
graph TD
    subgraph SwiftUI
        RV[RealityView]
        HUD[HUD Overlay\nSwiftUI + Metal shader]
        Gestures[DragGesture / SpatialTapGesture]
    end

    subgraph RealityKit ECS
        Entities[Entity Tree\nMotherboard + Puzzles]
        CurseState[CurseStateComponent]
        Draggable[DraggableComponent]
        CRS[CurseResolutionSystem\n per-frame update]
    end

    subgraph Domain Services
        GLS[GameLoopState\n@Observable]
        Buffer[CurseEventBuffer\nNSLock-protected]
        Factory[PuzzleFactory\nenum namespace]
        AR[ARSessionCoordinator]
    end

    subgraph Platform
        Haptics[HapticEngine\nCHHapticEngine wrapper]
        Audio[SpatialAudioCoordinator]
        Persist[GameStatePersistence\nSwift actor]
    end

    RV -->|make / update closures| Entities
    Gestures -->|targeted to entity| Draggable
    CRS -->|post events| Buffer
    Buffer -->|drainEvents| GLS
    GLS -->|@Observable| HUD
    GLS -->|session phase| RV
    AR -->|ARPlaneAnchor| Entities
    Factory -->|builds entity trees| Entities
    GLS -->|triggers| Haptics
    GLS -->|triggers| Audio
    GLS -->|scenePhase| Persist
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Gesture API | `DragGesture().targetedToAnyEntity()` | SwiftUI-native; avoids manual raycasting (Req 4.1, 4.3) |
| ECS↔SwiftUI bridge | `CurseEventBuffer` + `@Observable` | Keeps ECS `update()` off `@MainActor` (Req 3.6, 3.7) |
| Simulator fallback | `AnchorEntity(world: .zero)` | Enables full 3D puzzle testing without ARKit hardware (Req 2.5) |
| Persistence | `Swift actor` + `Codable` + versioned schema | Thread-safe, no external dependencies, version-aware migration (Req 11) |
| HUD visual FX | Metal `.layerEffect` shader | GPU compositing; no UIKit dependency |
| Gesture hit-testing | `InputTargetComponent` + `CollisionComponent` on every Fix Entity | Required for `DragGesture().targetedToAnyEntity()` to fire; without them RealityKit ignores the entity entirely |

---

## Components and Interfaces

### 1. Swift File/Folder Directory Structure

```
PoltergeistDebugger/
├── PoltergeistDebuggerApp.swift          ← @main entry point
├── ContentView.swift                     ← Root SwiftUI scene
│
├── AR/
│   ├── ARSessionCoordinator.swift        ← ARKit delegate, plane detection
│   └── SimulatorFallback.swift           ← AnchorEntity(world: .zero) path
│
├── ECS/
│   ├── Components/
│   │   ├── CurseStateComponent.swift
│   │   ├── DraggableComponent.swift
│   │   └── SnapZoneComponent.swift       ← optional marker component
│   └── Systems/
│       ├── CurseResolutionSystem.swift
│       └── DragReturnSystem.swift        ← animates released entities back
│
├── Puzzles/
│   ├── PuzzleFactory.swift               ← static factory namespace
│   ├── MemoryLeakPuzzle.swift            ← puzzle-specific helpers (particles)
│   ├── RaceConditionPuzzle.swift         ← gear physics helpers
│   └── DanglingPointerPuzzle.swift       ← drift animation helpers
│
├── HUD/
│   ├── HUDView.swift                     ← SwiftUI overlay
│   ├── ScanningView.swift                ← plane-search indicator
│   ├── VictoryOverlayView.swift          ← "All Bugs Exorcised" screen
│   └── Shaders/
│       └── PoltergeistHUD.metal          ← desaturation / vignette / grain
│
├── Audio/
│   └── SpatialAudioCoordinator.swift     ← AudioFileResource management
│
├── Haptics/
│   └── HapticEngine.swift                ← CHHapticEngine wrapper
│
├── Persistence/
│   ├── GameStatePersistence.swift        ← Swift actor, save/load
│   ├── PersistedGameState.swift          ← Codable structs
│   └── EntityTransformSnapshot.swift
│
├── State/
│   ├── GameLoopState.swift               ← @Observable view model
│   ├── SessionPhase.swift                ← enum
│   └── CurseEventBuffer.swift            ← NSLock-protected event queue
│
├── Resources/
│   ├── Assets.xcassets/                  ← app icon, AR textures
│   ├── Audio/                            ← .m4a / .wav ambient & FX files
│   └── Models/                           ← .usdz entity models
│
└── Tests/
    ├── PoltergeistDebuggerTests/
    │   ├── SerializationTests.swift       ← round-trip property tests
    │   ├── CurseResolutionTests.swift     ← snap-radius property tests
    │   ├── EventBufferTests.swift         ← concurrency property tests
    │   └── GameLoopStateTests.swift       ← count invariant tests
    └── PoltergeistDebuggerUITests/
        └── ARFlowUITests.swift
```

---

### 2. ECS Component Signatures

```swift
// MARK: - CurseType

enum CurseType: String, Codable, CaseIterable, Sendable {
    case memoryLeak        = "memoryLeak"
    case raceCondition     = "raceCondition"
    case danglingPointer   = "danglingPointer"
}

// MARK: - CurseStateComponent

/// Attached to every Cursed Entity. Tracks whether the curse is active
/// and holds the spatial threshold for Fix-Entity proximity detection.
struct CurseStateComponent: Component, Codable {
    /// True while the curse is unresolved. Set to false by CurseResolutionSystem.
    var isCursed: Bool

    /// Identifies which puzzle this entity belongs to.
    var curseType: CurseType

    /// World-space radius (metres) within which a matching Fix Entity
    /// triggers curse resolution. Defaults to 0.12 m (Req 3.1).
    var snapRadius: Float

    init(curseType: CurseType, snapRadius: Float = 0.12) {
        self.isCursed    = true
        self.curseType   = curseType
        self.snapRadius  = snapRadius
    }
}

// MARK: - DraggableComponent

/// Marks an entity as eligible for SwiftUI DragGesture input.
/// Only entities carrying this component respond to drag gestures (Req 3.2).
struct DraggableComponent: Component {
    /// World-space resting position; used to animate return on release (Req 4.6).
    var restPosition: SIMD3<Float>

    /// True while the player's finger is actively dragging this entity.
    var isDragging: Bool

    /// Brightness multiplier at idle; stored so the 30% boost can be reversed (Req 4.4).
    var originalBrightness: Float

    init(restPosition: SIMD3<Float>, originalBrightness: Float = 1.0) {
        self.restPosition      = restPosition
        self.isDragging        = false
        self.originalBrightness = originalBrightness
    }
}
```

---

### 3. CurseResolutionSystem Signature

```swift
import RealityKit

/// Per-frame RealityKit system that detects Fix-Entity proximity to Cursed
/// Entities and triggers curse resolution when distance ≤ snapRadius (Req 3.3–3.7).
///
/// Threading contract: update(context:) is NOT @MainActor-isolated.
/// All GameLoopState communication is routed through CurseEventBuffer.
final class CurseResolutionSystem: System {

    // Shared event buffer injected at registration time.
    private let eventBuffer: CurseEventBuffer

    // Track which curseTypes have already been resolved this session
    // to prevent duplicate notifications (Req 3.5).
    private var resolvedCurseTypes: Set<CurseType> = []

    // Query: entities that are currently cursed and awaiting resolution.
    private static let cursedQuery = EntityQuery(
        where: .has(CurseStateComponent.self)
    )

    // Query: entities the player can drag (Fix Entities).
    private static let fixQuery = EntityQuery(
        where: .has(DraggableComponent.self)
    )

    // Registration is called once at app launch in PoltergeistDebuggerApp.init()
    // — NOT here. Calling registerSystem() inside init() creates a recursive cycle.
    required init(scene: Scene) {
        // CurseEventBuffer is retrieved from a shared accessor so the
        // System can be instantiated by RealityKit's runtime (Req 3.7).
        self.eventBuffer = CurseEventBuffer.shared
    }

    func update(context: SceneUpdateContext) {
        // Collect all fix-entity world positions once per frame.
        let fixEntities: [(entity: Entity, curseType: CurseType?)] =
            context.entities(matching: Self.fixQuery, updatingSystemWhen: .rendering)
            .compactMap { entity in
                // Fix entities carry a CurseStateComponent to declare their type.
                guard let drag = entity.components[DraggableComponent.self] else { return nil }
                let curseType = entity.components[CurseStateComponent.self]?.curseType
                return (entity, curseType)
            }

        // Evaluate each cursed entity against every fix entity.
        for cursedEntity in context.entities(matching: Self.cursedQuery, updatingSystemWhen: .rendering) {
            guard var curseState = cursedEntity.components[CurseStateComponent.self],
                  curseState.isCursed else { continue }

            let origin = cursedEntity.position(relativeTo: nil)

            for fix in fixEntities {
                // Req 5.4 / 6.3: only the matching fix type triggers resolution.
                guard fix.curseType == curseState.curseType else { continue }

                // Prevent self-resolution: a Fix Entity must not be the same entity as its
                // target Cursed Entity (guards the DanglingPointer puzzle — Fix 3).
                guard fix.entity.id != cursedEntity.id else { continue }

                let fixPos  = fix.entity.position(relativeTo: nil)
                let dist    = distance(fixPos, origin)

                if dist <= curseState.snapRadius {
                    // Mutate component — marks resolved.
                    curseState.isCursed = false
                    cursedEntity.components[CurseStateComponent.self] = curseState

                    // Post exactly one event per curse type (Req 3.5).
                    if !resolvedCurseTypes.contains(curseState.curseType) {
                        resolvedCurseTypes.insert(curseState.curseType)
                        eventBuffer.post(
                            CurseResolvedEvent(curseType: curseState.curseType)
                        )
                    }
                    break
                }
            }
        }
    }
}
```

---

### 3a. Registration at App Launch

```swift
// In PoltergeistDebuggerApp.swift

@main
struct PoltergeistDebuggerApp: App {

    init() {
        // Register all custom ECS components and systems exactly once,
        // before any RealityView is instantiated (Fix 4).
        CurseStateComponent.registerComponent()
        DraggableComponent.registerComponent()
        CurseResolutionSystem.registerSystem()
        DragReturnSystem.registerSystem()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

---

### 4. Thread-Safe Event Buffer

Satisfies Req 3.6 and 3.7: `CurseResolutionSystem.update(context:)` runs off `@MainActor`; `GameLoopState.processEvents()` is `@MainActor`-isolated.

```swift
import Foundation

// MARK: - CurseResolvedEvent

/// Value emitted by CurseResolutionSystem when a curse is resolved.
struct CurseResolvedEvent: Sendable, Equatable {
    let curseType: CurseType
    let timestamp: Date

    init(curseType: CurseType, timestamp: Date = .now) {
        self.curseType = curseType
        self.timestamp = timestamp
    }
}

// MARK: - CurseEventBuffer

/// NSLock-protected FIFO queue.
///
/// - Written from the RealityKit system thread via `post(_:)`.
/// - Drained on the main actor via `drainEvents()`.
///
/// The `shared` singleton is the only instance used in production; tests
/// may create isolated instances for deterministic verification.
final class CurseEventBuffer: @unchecked Sendable {

    static let shared = CurseEventBuffer()

    private let lock    = NSLock()
    private var pending: [CurseResolvedEvent] = []

    /// Called by CurseResolutionSystem (off main actor). O(1) amortised.
    func post(_ event: CurseResolvedEvent) {
        lock.withLock { pending.append(event) }
    }

    /// Called by GameLoopState (@MainActor). Atomically swaps the buffer
    /// and returns all accumulated events. Each event is returned exactly once.
    func drainEvents() -> [CurseResolvedEvent] {
        lock.withLock {
            let events = pending
            pending = []
            return events
        }
    }
}
```

---

### 5. GameLoopState (@Observable)

```swift
import Observation
import Combine

// MARK: - SessionPhase

enum SessionPhase: String, Codable, Sendable {
    case scanning   // ARKit searching for a horizontal plane
    case playing    // Motherboard anchored; puzzles active
    case victory    // All three puzzles resolved
}

// MARK: - GameLoopState

@Observable
@MainActor
final class GameLoopState {

    // MARK: Published State

    /// Current phase of the AR game session (Req 1.7, 10.3).
    var sessionPhase: SessionPhase = .scanning

    /// Number of resolved puzzles; clamped to 0–3 (Req 10.1).
    private(set) var resolvedCount: Int = 0

    /// Curses that are still active (isCursed == true) (Req 10.2).
    var activeCurses: [CurseType] = CurseType.allCases

    // MARK: Dependencies

    /// Shared event buffer written by CurseResolutionSystem.
    let eventBuffer: CurseEventBuffer

    init(eventBuffer: CurseEventBuffer = .shared) {
        self.eventBuffer = eventBuffer
    }

    // MARK: Event Processing

    /// Drain all pending ECS events and update observable state.
    /// Called from the RealityView `update:` closure each frame (Req 3.7).
    func processEvents() {
        let events = eventBuffer.drainEvents()
        for event in events {
            handleResolution(of: event.curseType)
        }
    }

    // MARK: Private

    private func handleResolution(of curseType: CurseType) {
        // Req 10.7: ignore resolution events once victory is reached.
        guard sessionPhase != .victory else { return }

        activeCurses.removeAll { $0 == curseType }

        // Req 10.1: resolvedCount is bounded [0, 3].
        resolvedCount = min(resolvedCount + 1, 3)

        // Req 10.3: transition to victory within 1 s of third puzzle resolving.
        if resolvedCount == 3 {
            sessionPhase = .victory
        }
    }

    // MARK: Restart (Req 10.6)

    func restartSession() {
        resolvedCount = 0
        activeCurses  = CurseType.allCases
        sessionPhase  = .playing
        eventBuffer.drainEvents()   // discard stale events
    }
}
```

---

### 6. AR Session Setup & Simulator Fallback

#### Configuration in `RealityView make:` closure

```swift
RealityView { content in
    if ARWorldTrackingConfiguration.isSupported {
        // Real device: configure ARKit for horizontal plane detection (Req 1.2).
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        content.session.run(config)

        // Plane anchor will be set via EventSubscription below.
        let motherboard = PuzzleFactory.makeMotherboard()
        content.add(motherboard)
    } else {
        // Simulator fallback: anchor at world origin (Req 2.5).
        let anchor = AnchorEntity(world: .zero)
        let motherboard = PuzzleFactory.makeMotherboard()
        anchor.addChild(motherboard)
        content.add(anchor)
    }
} update: { content in
    gameLoopState.processEvents()
}
```

#### Plane Detection via EventSubscription

RealityKit 2 exposes ARKit anchor events through the scene's event system. The coordinator subscribes to `SceneEvents.AnchoredStateChanged` and `ARKitAnchorStateChanged` to react to detected planes:

```swift
// In ARSessionCoordinator.swift, called once from RealityView make:
func subscribeToPlaneEvents(scene: RealityKit.Scene) {
    // Listen for horizontal planes; choose the largest (Req 1.3, 1.4).
    planeSubscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
        self?.evaluatePlanes()
    }
}

private func evaluatePlanes() {
    guard !motherboardAnchored else { return }
    if let best = detectedPlanes.max(by: { $0.extent.area < $1.extent.area }),
       (best.planeExtent.width * best.planeExtent.height) >= 0.09 {
        anchorMotherboard(to: best)
        motherboardAnchored = true
        gameLoopState.sessionPhase = .playing   // Req 1.7
    }
}
```

The `ARWorldTrackingConfiguration.isSupported` guard is the sole branching point — no `#if targetEnvironment(simulator)` is needed, keeping the build clean.

---

### 7. Puzzle Entity Factory

```swift
// MARK: - PuzzleFactory

/// Static factory namespace that constructs fully configured RealityKit entity
/// trees for each puzzle. All component attachment happens here, keeping
/// puzzle logic out of view code.
enum PuzzleFactory {

    // MARK: Motherboard Root

    /// Creates the root entity anchored to the detected plane.
    static func makeMotherboard() -> Entity {
        let root = Entity()
        root.name = "Motherboard"
        // Attach puzzle sub-trees
        root.addChild(makeMemoryLeakPuzzle())
        root.addChild(makeRaceConditionPuzzle())
        root.addChild(makeDanglingPointerPuzzle())
        return root
    }

    // MARK: Puzzle 1 — Memory Leak

    /// Returns the RAM bank entity (Cursed) plus the Deallocator Fix Entity.
    ///
    /// Components attached to RAM bank: CurseStateComponent(.memoryLeak),
    ///   ParticleEmitterComponent (green mist), AudioFileResource (loop)
    /// Components attached to Deallocator: DraggableComponent,
    ///   CurseStateComponent(curseType: .memoryLeak) ← type tag for matching,
    ///   InputTargetComponent, CollisionComponent ← required for gesture targeting
    static func makeMemoryLeakPuzzle() -> Entity {
        let root = Entity()
        root.name = "MemoryLeakPuzzle"

        // Cursed entity: RAM bank
        let ram = ModelEntity(mesh: .generateBox(size: 0.08),
                              materials: [SimpleMaterial(color: .green, isMetallic: true)])
        ram.name = "RAMBank"
        ram.components.set(CurseStateComponent(curseType: .memoryLeak))
        ram.components.set(makeGreenParticleEmitter())
        ram.position = SIMD3(0, 0.01, -0.05)

        // Fix entity: Deallocator tool
        let deallocator = ModelEntity(mesh: .generateSphere(radius: 0.02),
                                      materials: [SimpleMaterial(color: .red, isMetallic: false)])
        deallocator.name = "Deallocator"
        let restPos = SIMD3<Float>(0.15, 0.02, -0.05)
        deallocator.position = restPos
        deallocator.components.set(DraggableComponent(restPosition: restPos))
        deallocator.components.set(CurseStateComponent(curseType: .memoryLeak, snapRadius: 0.0))
        deallocator.components.set(InputTargetComponent())
        deallocator.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.02)]))
        // snapRadius 0.0 on fix entity — it is not a target, only a type tag

        root.addChild(ram)
        root.addChild(deallocator)
        return root
    }

    // MARK: Puzzle 2 — Race Condition

    /// Returns two gear entities (Cursed) plus the Mutex Lock Fix Entity.
    ///
    /// Components attached to each gear: CurseStateComponent(.raceCondition),
    ///   PhysicsMotionComponent (mismatched angular velocities), ParticleEmitterComponent (sparks),
    ///   PhysicsBodyComponent(.kinematic)
    /// Components attached to Mutex Lock: DraggableComponent,
    ///   CurseStateComponent(curseType: .raceCondition) ← type tag,
    ///   InputTargetComponent, CollisionComponent ← required for gesture targeting
    static func makeRaceConditionPuzzle() -> Entity {
        let root = Entity()
        root.name = "RaceConditionPuzzle"

        func makeGear(name: String,
                      angularVelocity: Float,
                      position: SIMD3<Float>) -> Entity {
            let gear = ModelEntity(mesh: .generateCylinder(height: 0.01, radius: 0.03),
                                   materials: [SimpleMaterial(color: .gray, isMetallic: true)])
            gear.name = name
            gear.position = position
            var motion = PhysicsMotionComponent()
            motion.angularVelocity = SIMD3(0, angularVelocity, 0)  // Req 6.1
            gear.components.set(motion)
            // PhysicsBodyComponent (kinematic mode) is required for PhysicsMotionComponent
            // to actually spin the mesh in RealityKit. Without it the gear renders but
            // does not rotate (Fix 5).
            gear.components.set(PhysicsBodyComponent(
                massProperties: .default,
                material:       .default,
                mode:           .kinematic
            ))
            gear.components.set(CurseStateComponent(curseType: .raceCondition))
            gear.components.set(makeSparkParticleEmitter())
            return gear
        }

        let gear1 = makeGear(name: "Gear1", angularVelocity: 3.0, position: SIMD3(-0.04, 0.01, 0.05))
        let gear2 = makeGear(name: "Gear2", angularVelocity: 7.0, position: SIMD3( 0.04, 0.01, 0.05))

        let mutexPos = SIMD3<Float>(0.18, 0.02, 0.05)
        let mutex = ModelEntity(mesh: .generateBox(size: 0.02),
                                materials: [SimpleMaterial(color: .yellow, isMetallic: false)])
        mutex.name = "MutexLock"
        mutex.position = mutexPos
        mutex.components.set(DraggableComponent(restPosition: mutexPos))
        mutex.components.set(CurseStateComponent(curseType: .raceCondition, snapRadius: 0.0))
        mutex.components.set(InputTargetComponent())
        mutex.components.set(CollisionComponent(shapes: [.generateBox(size: [0.02, 0.02, 0.02])]))

        root.addChild(gear1)
        root.addChild(gear2)
        root.addChild(mutex)
        return root
    }

    // MARK: Puzzle 3 — Dangling Pointer

    /// Returns a root AnchorEntity (the snap target, attached to Motherboard) plus a
    /// detached drifting ModelEntity (the fix tool, added at world level).
    ///
    /// Components on DanglingPointerAnchor (root, on Motherboard):
    ///   CurseStateComponent(.danglingPointer, snapRadius: 0.12) ← resolution target
    ///
    /// Components on DanglingPointer (drifter, world-level):
    ///   DraggableComponent, CurseStateComponent(.danglingPointer, snapRadius: 0.0) ← type tag only
    ///   InputTargetComponent, CollisionComponent ← required for gesture targeting
    ///
    /// CurseResolutionSystem compares drifter.position → anchor.position. Because the
    /// drifter's snapRadius is 0.0, it is never evaluated as a target — preventing
    /// the self-collision auto-resolve on frame 1 (Fix 3).
    static func makeDanglingPointerPuzzle() -> Entity {
        // This root is a placeholder added to the motherboard so the factory
        // always returns a single Entity; the floating ModelEntity is returned
        // separately through the scene content and added at world level.
        let root = Entity()
        root.name = "DanglingPointerAnchor"
        // DanglingPointerAnchor on the Motherboard holds the resolution target component.
        root.components.set(CurseStateComponent(curseType: .danglingPointer, snapRadius: 0.12))

        let drifter = ModelEntity(mesh: .generateBox(size: SIMD3(0.03, 0.01, 0.03)),
                                  materials: [SimpleMaterial(color: .purple, isMetallic: false)])
        drifter.name = "DanglingPointer"
        let driftStart = SIMD3<Float>(0, 0.12, -0.1)
        drifter.position = driftStart
        // DanglingPointer is ONLY a draggable fix tool — it carries a type tag but NOT
        // a snapRadius target. The CurseStateComponent with isCursed=true and snapRadius
        // lives on the DanglingPointerAnchor entity on the Motherboard, so
        // CurseResolutionSystem compares drifter→anchor, never drifter→itself.
        drifter.components.set(DraggableComponent(restPosition: driftStart))
        // Type tag only — snapRadius 0.0 means this entity is never a resolution target.
        drifter.components.set(CurseStateComponent(curseType: .danglingPointer, snapRadius: 0.0))
        drifter.components.set(InputTargetComponent())
        drifter.components.set(CollisionComponent(shapes: [.generateBox(size: [0.03, 0.01, 0.03])]))
        // Drift animation applied separately by DanglingPointerPuzzle helper

        root.addChild(drifter)
        return root
    }

    // MARK: - Particle Helpers

    private static func makeGreenParticleEmitter() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.mainEmitter.birthRate           = 200
        emitter.mainEmitter.color               = .constant(.single(.green))
        emitter.mainEmitter.lifeSpan            = 1.5
        emitter.isEmitting                      = true
        return emitter
    }

    private static func makeSparkParticleEmitter() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.mainEmitter.birthRate           = 80
        emitter.mainEmitter.color               = .constant(.single(.yellow))
        emitter.mainEmitter.lifeSpan            = 0.4
        emitter.isEmitting                      = true
        return emitter
    }
}
```

---

### 8. Spatial Drag Gesture Architecture

SwiftUI 17+ exposes `DragGesture().targetedToAnyEntity()` which provides a `EntityTargetValue<DragGesture.Value>` containing both the 2D gesture value and the resolved 3D `location3D` in scene space.

#### View Modifier Chain

```swift
RealityView { ... } update: { ... }
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
```

#### 3D Position Computation

`EntityTargetValue` exposes `convert(_ location3D: Point3D, from: .local, to: .scene)` which maps the touch hit point into RealityKit scene coordinates. The drag handler sets the entity's world position each frame:

The `isDragging` flag guards the one-time setup (brightness boost + pickup haptic) but does NOT short-circuit the position update — the entity follows the finger on every `onChanged` callback.

```swift
func handleChanged(_ value: EntityTargetValue<DragGesture.Value>) {
    guard var draggable = value.entity.components[DraggableComponent.self] else { return }

    // One-time setup on first frame of drag: boost brightness and fire pickup haptic (Req 4.4).
    if !draggable.isDragging {
        draggable.isDragging = true
        value.entity.components.set(draggable)
        applyBrightnessBoost(to: value.entity, multiplier: 1.3)
        HapticEngine.shared.playPickup()
    }

    // Every frame: update world-space position to follow the touch (Req 4.1).
    let scenePos = value.convert(value.location3D, from: .local, to: .scene)
    value.entity.setPosition(SIMD3(scenePos), relativeTo: nil)
}
```

#### Return Animation

When the player lifts their finger outside a Snap Zone, `DragReturnSystem` (a secondary ECS system) detects `isDragging == false` and animates back to `restPosition` using `FromToByAnimation` with an ease-out curve over 0.2–0.5 s (Req 4.6):

```swift
func handleEnded(_ value: EntityTargetValue<DragGesture.Value>) {
    guard var draggable = value.entity.components[DraggableComponent.self] else { return }
    draggable.isDragging = false
    value.entity.components.set(draggable)
    removeBrightnessBoost(from: value.entity)
    // DragReturnSystem picks this up next frame and drives the animation.
}
```

---

## Data Models

### 9. Codable JSON Persistence Schema (Req 11)

#### Codable Structs

```swift
// MARK: - EntityTransformSnapshot

/// Flattened representation of a RealityKit Transform for JSON persistence.
struct EntityTransformSnapshot: Codable, Equatable {
    var positionX: Float
    var positionY: Float
    var positionZ: Float
    var rotationX: Float   // simd_quatf imaginary i
    var rotationY: Float   // simd_quatf imaginary j
    var rotationZ: Float   // simd_quatf imaginary k
    var rotationW: Float   // simd_quatf real part
    var scale: Float       // uniform scale

    // MARK: Convenience

    var position: SIMD3<Float>  { SIMD3(positionX, positionY, positionZ) }
    var rotation: simd_quatf    { simd_quatf(ix: rotationX, iy: rotationY, iz: rotationZ, r: rotationW) }

    init(transform: Transform) {
        positionX = transform.translation.x
        positionY = transform.translation.y
        positionZ = transform.translation.z
        rotationX = transform.rotation.imag.x
        rotationY = transform.rotation.imag.y
        rotationZ = transform.rotation.imag.z
        rotationW = transform.rotation.real
        scale     = transform.scale.x   // uniform assumed
    }
}

// MARK: - PersistedGameState

/// Top-level Codable payload stored in Documents/poltergeist_save.json.
struct PersistedGameState: Codable, Equatable {
    /// Incremented when the schema changes; current value: 1 (Req 11.6).
    let schemaVersion: Int

    /// Maps CurseType.rawValue → resolved flag (Req 11.1).
    var resolvedPuzzles: [String: Bool]

    /// Maps entity name → transform snapshot (Req 11.1).
    var entitySnapshots: [String: EntityTransformSnapshot]

    /// SessionPhase.rawValue (Req 11.1).
    var sessionPhase: String

    static let currentSchemaVersion = 1
}
```

#### GameStatePersistence Actor

```swift
import Foundation

// MARK: - GameStatePersistence

/// Thread-safe persistence actor. All file I/O is isolated to this actor,
/// so GameLoopState (@MainActor) can call save/load without data races.
actor GameStatePersistence {

    static let shared = GameStatePersistence()

    // MARK: Private

    private let saveURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("poltergeist_save.json")   // Req 11.3
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private let decoder = JSONDecoder()

    // MARK: Public Interface

    /// Serializes and writes state to disk (Req 11.1).
    /// Throws on encoding or write failure so the caller can surface the error (Req 11.7).
    func save(_ state: PersistedGameState) async throws {
        let data = try encoder.encode(state)
        try data.write(to: saveURL, options: .atomicWrite)
    }

    /// Loads persisted state (Req 11.2).
    /// Returns nil and deletes the corrupted file if schema version mismatches (Req 11.4).
    func load() async -> PersistedGameState? {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return nil }
        do {
            let data   = try Data(contentsOf: saveURL)
            let state  = try decoder.decode(PersistedGameState.self, from: data)
            guard state.schemaVersion == PersistedGameState.currentSchemaVersion else {
                try? FileManager.default.removeItem(at: saveURL)
                // Req 11.4: log and return nil → caller initialises fresh state
                print("[Persistence] Schema mismatch — discarding save file.")
                return nil
            }
            return state
        } catch {
            try? FileManager.default.removeItem(at: saveURL)
            print("[Persistence] Malformed save file: \(error)")
            return nil
        }
    }
}
```

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Serialization Round-Trip

*For any* valid `PersistedGameState` value (with any combination of resolved puzzles, entity snapshots, and session phase), encoding it to JSON then decoding the result SHALL produce a `PersistedGameState` whose `resolvedPuzzles`, `entitySnapshots`, and `sessionPhase` fields are each equal to those of the original.

**Validates: Requirements 11.5, 11.2**

---

### Property 2: Snap Triggers Resolution

*For any* cursed entity with a given `snapRadius` and any matching Fix Entity (same `curseType`) whose world-space distance to that entity's origin is less than or equal to `snapRadius`, after one `CurseResolutionSystem.update(context:)` execution the cursed entity's `CurseStateComponent.isCursed` SHALL be `false`.

**Validates: Requirements 3.4, 4.5, 5.3, 6.3, 7.3**

---

### Property 3: Out-of-Radius Leaves Curse Unchanged

*For any* cursed entity and any Fix Entity whose world-space distance to that entity's origin is strictly greater than `snapRadius`, after one `CurseResolutionSystem.update(context:)` execution the cursed entity's `CurseStateComponent.isCursed` SHALL remain `true`.

**Validates: Requirements 5.5, 7.7**

---

### Property 4: Event Buffer Completeness Under Concurrency

*For any* sequence of concurrent `post(_:)` calls to a `CurseEventBuffer`, a single subsequent call to `drainEvents()` SHALL return a collection containing exactly every event that was posted — no omissions and no duplicates — and a second call to `drainEvents()` immediately after SHALL return an empty collection.

**Validates: Requirements 3.5, 3.7**

---

### Property 5: Resolved Count Bounded and Monotonic

*For any* sequence of `handleResolution(of:)` calls on `GameLoopState`, the `resolvedCount` SHALL never exceed 3, SHALL never decrease, and SHALL equal the number of distinct `CurseType` values that have been resolved so far in the sequence.

**Validates: Requirements 10.1, 10.7**

---

### Property 6: Victory Entered Exactly When resolvedCount Reaches 3

*For any* `GameLoopState` starting in `.playing` phase, after the third distinct puzzle resolution event is processed the `sessionPhase` SHALL be `.victory`, and processing any further resolution events SHALL leave `sessionPhase` unchanged at `.victory`.

**Validates: Requirements 10.3, 10.7**

---

### Property 7: Wrong-Type Fix Entity Leaves Curse Unchanged

*For any* cursed entity of type T and any Fix Entity of type T′ where T′ ≠ T, regardless of the Fix Entity's distance from the cursed entity's origin, after one `CurseResolutionSystem.update(context:)` execution the cursed entity's `CurseStateComponent.isCursed` SHALL remain `true`.

**Validates: Requirements 5.4**

---

### Property 8: Particle Emitter Active While Cursed

*For any* puzzle entity whose `CurseStateComponent.isCursed` is `true`, the `ParticleEmitterComponent` attached to that entity SHALL have `isEmitting == true`; conversely, when `isCursed` transitions to `false`, `isEmitting` SHALL be `false`.

**Validates: Requirements 5.2, 6.2**

---

### Property 9: Victory Haptic Contains Exactly Three Beats

*For any* call to `HapticEngine.playVictory()`, the constructed `CHHapticPattern` SHALL contain exactly 3 `CHHapticEvent` instances, each with intensity in the range 0.6–1.0 and each separated from the next by a gap of 0.10–0.15 seconds.

**Validates: Requirements 8.4**

---

### Property 10: Restart Round-Trips to Clean Playing State

*For any* `GameLoopState` in `.victory` phase (regardless of which order the three puzzles were resolved), calling `restartSession()` SHALL produce a `GameLoopState` where `resolvedCount == 0`, `activeCurses` contains all three `CurseType` values, and `sessionPhase == .playing`.

**Validates: Requirements 10.6**

---

### Property 11: Largest-Area Plane Is Always Selected for Anchoring

*For any* non-empty set of detected horizontal ARPlaneAnchors each with a distinct surface area ≥ 0.09 m², the `ARSessionCoordinator` SHALL anchor the Motherboard to the plane whose surface area is strictly greater than all others in the set.

**Validates: Requirements 1.4**

---

## Error Handling

| Scenario | Handling |
|---|---|
| Camera permission denied | Non-AR fallback screen + deep link to iOS Settings (Req 1.6) |
| ARKit tracking interrupted | HUD recovery indicator; no puzzle reset (Req 1.8) |
| ARKit not supported (Simulator) | `AnchorEntity(world: .zero)` fallback; full ECS functionality preserved (Req 2.5) |
| `CHHapticEngine` fails | Silent continue; no error UI shown to player (Req 8.6) |
| `AudioFileResource` fails to load | Log + continue; no gameplay interruption (Req 9.5) |
| Malformed / version-mismatched save file | Discard file, log warning, start fresh (Req 11.4) |
| Save write failure | Retain last valid save; show error to player within 3 s (Req 11.7) |
| Duplicate resolution event (resolvedCount == 3) | Event ignored; `victoryState` unchanged (Req 10.7) |
| Fix Entity dropped in occupied Snap Zone | Snap rejected; haptic rejection pulse; entity returns to rest (Req 4.8) |
| `DragGesture` lost mid-drag | Entity returns to rest within 0.5 s; no player input required (Req 4.7) |

---

## Testing Strategy

### Dual Testing Approach

Unit tests cover specific examples, edge cases, and error conditions. Property-based tests verify universal invariants across randomised inputs. Both are required for comprehensive coverage of this feature.

### Property-Based Testing Library

The project uses **swift-testing** (native to Xcode 16+) for regular tests and **swift-check** (a Swift port of QuickCheck / Hedgehog) for property-based tests. Each property test runs a minimum of **100 iterations**.

Property tests are tagged with:
```
// Feature: poltergeist-debugger, Property N: <property text>
```

### 12. Property-Based Test Descriptions

#### Property 1 — Serialization Round-Trip (Req 11.5)

```swift
// Feature: poltergeist-debugger, Property 1: Serialization round-trip
@Test func serializationRoundTrip() {
    forAll(Gen<PersistedGameState>.arbitrary) { state in
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedGameState.self, from: encoded)
        #expect(decoded == state)
    }
}
```

Generator constructs arbitrary `PersistedGameState` values by independently randomising `resolvedPuzzles` (all 2³ = 8 combinations of the three curse flags), `entitySnapshots` (random floats for each of the three entity transforms), and `sessionPhase` (one of the three raw values). The test verifies structural equality after the encode→decode round trip.

---

#### Properties 2 & 3 — CurseResolutionSystem Proximity (Req 3.4, 5.5)

```swift
// Feature: poltergeist-debugger, Property 2: Snap triggers resolution
@Test func snapRadiusTriggersResolution() {
    forAll(
        Gen<Float>.float(in: 0.01...0.30),   // arbitrary snapRadius
        Gen<Float>.float(in: 0.00...1.00)    // arbitrary distance multiplier 0–1×
    ) { snapRadius, multiplier in
        let dist = snapRadius * multiplier    // always ≤ snapRadius
        let (scene, cursed, fix) = makeTestScene(
            snapRadius: snapRadius, fixDistance: dist
        )
        CurseResolutionSystem.runOneFrame(scene: scene)
        #expect(cursed.components[CurseStateComponent.self]?.isCursed == false)
    }
}

// Feature: poltergeist-debugger, Property 3: Out-of-radius leaves curse unchanged
@Test func outsideRadiusLeavesUntouched() {
    forAll(
        Gen<Float>.float(in: 0.01...0.30),
        Gen<Float>.float(in: 1.001...3.0)    // strictly > 1× snapRadius
    ) { snapRadius, multiplier in
        let dist = snapRadius * multiplier
        let (scene, cursed, _) = makeTestScene(
            snapRadius: snapRadius, fixDistance: dist
        )
        CurseResolutionSystem.runOneFrame(scene: scene)
        #expect(cursed.components[CurseStateComponent.self]?.isCursed == true)
    }
}
```

`makeTestScene` is a test helper that creates an in-memory RealityKit `Scene`, places a cursed entity at the origin, and places a matching fix entity at the specified distance. `CurseResolutionSystem.runOneFrame` invokes `update(context:)` synchronously using a mock `SceneUpdateContext`.

---

#### Property 4 — Event Buffer Completeness Under Concurrency (Req 3.5, 3.7)

```swift
// Feature: poltergeist-debugger, Property 4: Event buffer completeness
@Test func eventBufferNeverDropsEvents() {
    forAll(Gen<Int>.int(in: 1...100)) { count in
        let buffer = CurseEventBuffer()
        let group  = DispatchGroup()

        // Simulate concurrent posts from multiple system threads
        for i in 0..<count {
            DispatchQueue.global().async(group: group) {
                buffer.post(CurseResolvedEvent(
                    curseType: CurseType.allCases[i % 3]
                ))
            }
        }
        group.wait()

        let drained = buffer.drainEvents()
        #expect(drained.count == count)
        // Second drain must be empty (no duplicates)
        #expect(buffer.drainEvents().isEmpty)
    }
}
```

---

#### Properties 5 & 6 — GameLoopState Invariants (Req 10.1, 10.3, 10.7)

```swift
// Feature: poltergeist-debugger, Property 5: resolvedCount bounded and monotonic
@Test func resolvedCountBoundedAndMonotonic() {
    forAll(
        Gen<[CurseType]>.array(of: Gen.element(of: CurseType.allCases), count: 1...20)
    ) { events in
        let state = await GameLoopState(eventBuffer: CurseEventBuffer())
        var previous = 0
        for curseType in events {
            await MainActor.run {
                state.handleResolution(of: curseType)
                #expect(state.resolvedCount >= previous)
                #expect(state.resolvedCount <= 3)
                previous = state.resolvedCount
            }
        }
    }
}

// Feature: poltergeist-debugger, Property 6: victory entered exactly when resolvedCount == 3
@Test func victoryEnteredExactlyOnThirdResolution() {
    forAll(
        Gen<[CurseType]>.shuffled(CurseType.allCases)
    ) { orderedCurses in
        let state = await GameLoopState(eventBuffer: CurseEventBuffer())
        for (index, curseType) in orderedCurses.enumerated() {
            await MainActor.run { state.handleResolution(of: curseType) }
            if index < 2 {
                await MainActor.run { #expect(state.sessionPhase != .victory) }
            }
        }
        await MainActor.run { #expect(state.sessionPhase == .victory) }

        // Further events must not change phase (Req 10.7)
        await MainActor.run {
            state.handleResolution(of: .memoryLeak)
            #expect(state.sessionPhase == .victory)
        }
    }
}
```

---

#### Property 7 — Wrong-Type Fix Leaves Curse Unchanged (Req 5.4)

```swift
// Feature: poltergeist-debugger, Property 7: wrong-type fix entity leaves curse unchanged
@Test func wrongTypeFixDoesNotResolve() {
    forAll(
        Gen<CurseType>.element(of: CurseType.allCases),
        Gen<Float>.float(in: 0.001...0.30)    // any distance, including inside snapRadius
    ) { targetType, dist in
        // Pick a fix type that is intentionally different
        let wrongType = CurseType.allCases.first { $0 != targetType }!
        let (scene, cursed, _) = makeTestScene(
            targetCurseType: targetType,
            fixCurseType: wrongType,
            snapRadius: 0.12,
            fixDistance: dist
        )
        CurseResolutionSystem.runOneFrame(scene: scene)
        #expect(cursed.components[CurseStateComponent.self]?.isCursed == true)
    }
}
```

---

#### Property 8 — Particle Emitter Active While Cursed (Req 5.2, 6.2)

```swift
// Feature: poltergeist-debugger, Property 8: particle emitter active while cursed
@Test func particleEmitterReflectsCurseState() {
    forAll(Gen<Bool>.bool) { startCursed in
        // Create a puzzle entity and set isCursed
        let ramBank = PuzzleFactory.makeMemoryLeakPuzzle()
            .findEntity(named: "RAMBank")!
        ramBank.components[CurseStateComponent.self]?.isCursed = startCursed
        // Simulate the particle update logic
        MemoryLeakPuzzle.syncParticleEmitter(on: ramBank)
        let emitting = ramBank.components[ParticleEmitterComponent.self]?.isEmitting
        #expect(emitting == startCursed)
    }
}
```

---

#### Property 9 — Victory Haptic Contains Exactly Three Beats (Req 8.4)

```swift
// Feature: poltergeist-debugger, Property 9: victory haptic contains exactly 3 beats
@Test func victoryHapticHasExactlyThreeBeats() {
    // playVictory is deterministic; property test verifies the invariant
    // holds regardless of call count / timing context.
    forAll(Gen<Int>.int(in: 1...100)) { _ in
        let capturedPattern = HapticEngine.makeVictoryPattern()
        let events = capturedPattern?.events ?? []
        #expect(events.count == 3)
        for i in 0..<2 {
            let gap = Double(events[i + 1].relativeTime) - Double(events[i].relativeTime)
            #expect(gap >= 0.10 && gap <= 0.15)
        }
    }
}
```

---

#### Property 10 — Restart Round-Trips to Clean Playing State (Req 10.6)

```swift
// Feature: poltergeist-debugger, Property 10: restart round-trips to clean playing state
@Test func restartProducesCleanPlayingState() {
    forAll(
        Gen<[CurseType]>.shuffled(CurseType.allCases)
    ) { orderedCurses in
        let state = await GameLoopState(eventBuffer: CurseEventBuffer())
        for curseType in orderedCurses {
            await MainActor.run { state.handleResolution(of: curseType) }
        }
        await MainActor.run {
            state.restartSession()
            #expect(state.resolvedCount == 0)
            #expect(Set(state.activeCurses) == Set(CurseType.allCases))
            #expect(state.sessionPhase == .playing)
        }
    }
}
```

---

#### Property 11 — Largest-Area Plane Is Selected (Req 1.4)

```swift
// Feature: poltergeist-debugger, Property 11: largest-area plane is always selected
@Test func largestPlaneIsAlwaysAnchored() {
    forAll(
        Gen<[Float]>.array(of: Gen<Float>.float(in: 0.1...5.0), count: 1...10)
    ) { areas in
        let planes = areas.map { MockARPlaneAnchor(area: $0) }
        let chosen = ARSessionCoordinator.selectBestPlane(from: planes)
        let maxArea = areas.max()!
        #expect(chosen?.area == maxArea)
    }
}
```

---

### Unit Test Coverage

| Area | Example Tests |
|---|---|
| AR init | Camera permission denied → fallback screen shown; permission granted → ARWorldTrackingConfiguration initialized with `.horizontal` |
| Simulator fallback | `ARWorldTrackingConfiguration.isSupported == false` → `AnchorEntity(world: .zero)` used |
| Puzzle factory | Each factory method attaches the correct components (verified by inspecting `components` set on returned entities) |
| Haptic engine | `playVictory()` fires 3 beats; intensity values within Req 8.4 ranges; `playSnap()` and `playPickup()` within their respective ranges |
| Haptic interruption | Calling `play*()` while pattern active cancels in-progress pattern (Req 8.5) |
| Persistence | Malformed JSON returns `nil` and the file is deleted (Req 11.4); schema version mismatch triggers discard |
| Persistence file path | Save URL always resolves to `Documents/poltergeist_save.json` (Req 11.3) |
| Save write failure | Previous file is retained; error is surfaced within 3 s (Req 11.7) |
| Drag gesture return | Entity returns to `restPosition` when dropped outside Snap Zone (Req 4.6) |
| Drag gesture lost | Gesture interruption mid-drag → entity returns to rest within 0.5 s (Req 4.7) |
| Occupied Snap Zone | Second entity dropped on occupied zone is rejected; haptic rejection fired (Req 4.8) |
| Race Condition puzzle | Gear angular velocities set to 5.0 rad/s after resolution (Req 6.4); sparks disabled (Req 6.5) |
| Dangling Pointer puzzle | `setParent()` called on proximity (Req 7.3); drifting resumes if released outside radius (Req 7.7) |
| Memory Leak puzzle | Particle emission halts and success sound plays on resolution (Req 5.6) |
| Victory overlay | `victoryState` entry displays "All Bugs Exorcised" overlay and restart button (Req 10.5) |
| Victory audio unavailable | Victory overlay shown without audio when asset missing (Req 10.8) |
| ARKit tracking interruption | Recovery indicator shown; `resolvedCount` unchanged (Req 1.8) |

---

### 10. Metal Shader — HUD `.layerEffect`

#### Shader File: `PoltergeistHUD.metal`

```metal
#include <SwiftUI/SwiftUI.h>
#include <metal_stdlib>
using namespace metal;

/// Applies three composited effects to the HUD layer:
///   1. Desaturation  — removes colour information, leaving a grey-scale ghost aesthetic.
///   2. Vignette      — darkens frame edges with a smooth radial falloff.
///   3. Film grain    — overlays a time-varying noise texture for an analogue horror feel.
///
/// Parameters
///   position  — fragment position in pixels.
///   layer     — the underlying SwiftUI layer to sample.
///   size      — full size of the layer in pixels (passed as float2 argument).
///   time      — elapsed time in seconds (passed as float argument, drives grain animation).
[[stitchable]] half4 poltergeistHUD(
    float2          position,
    SwiftUI::Layer  layer,
    float2          size,
    float           time
) {
    // Sample the original colour.
    half4 colour = layer.sample(position);

    // 1. Desaturation (NTSC luminance weights).
    float luma = dot(float3(colour.rgb), float3(0.2126, 0.7152, 0.0722));
    half3 desaturated = half3(luma);

    // 2. Vignette — radial darkening (Req 2.3).
    float2 uv     = (position / size) * 2.0 - 1.0;  // normalise to [-1, 1]
    float  vDist  = dot(uv, uv);                     // squared distance from centre
    float  vign   = 1.0 - smoothstep(0.4, 1.2, vDist);

    // 3. Film grain (Req 2.3) — pseudo-random noise, animated by time.
    float2 noiseUV  = position * 0.005 + fract(time * 0.37);
    float  grain    = fract(sin(dot(noiseUV, float2(127.1, 311.7))) * 43758.5453);
    float  grainAmt = 0.08;  // grain opacity

    half3 result = desaturated * half(vign) + half3(grain * grainAmt);
    return half4(result, colour.a);
}
```

#### SwiftUI Call Site

```swift
// In HUDView.swift
var body: some View {
    hudContent
        .layerEffect(
            ShaderLibrary.poltergeistHUD(
                .float2(geometry.size),
                .float(elapsedTime)           // animated via TimelineView
            ),
            maxSampleOffset: .zero
        )
}
```

`elapsedTime` is driven by a `TimelineView(.animation)` so the grain animates per frame. `maxSampleOffset: .zero` is correct here because the shader only reads the pixel at the sample point — it does not blur or displace neighbours.

---

### 11. CoreHaptics Engine Lifecycle

```swift
import CoreHaptics

/// Wraps CHHapticEngine, handling start/stop lifecycle and named haptic
/// patterns for each game interaction (Req 8.1–8.7).
@MainActor
final class HapticEngine {

    static let shared = HapticEngine()

    private var engine: CHHapticEngine?
    private var currentPlayer: CHHapticPatternPlayer?

    // MARK: Lifecycle

    /// Called when the game session starts (Req 8.1).
    func start() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            engine?.stoppedHandler = { [weak self] _ in
                try? self?.engine?.start()   // auto-restart on interruption
            }
            try engine?.start()
        } catch {
            // Req 8.6: silent failure — gameplay continues without haptics.
            engine = nil
        }
    }

    /// Called when the app enters the background (Req 8.1).
    func stop() {
        engine?.stop()
    }

    // MARK: Haptic Patterns

    /// Snap haptic: intensity 0.7–1.0, duration 0.08–0.12 s (Req 8.2).
    func playSnap() {
        play(pattern: makePattern(
            events: [CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0,
                duration: 0.10
            )]
        ))
    }

    /// Pickup haptic: intensity 0.2–0.4, duration 0.05–0.10 s (Req 8.3).
    func playPickup() {
        play(pattern: makePattern(
            events: [CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: 0,
                duration: 0.07
            )]
        ))
    }

    /// Victory haptic: exactly 3 beats, each 0.6–1.0 intensity,
    /// separated by 0.10–0.15 s gaps (Req 8.4).
    func playVictory() {
        let beatSpacing = 0.12  // seconds between beat starts
        let beats: [CHHapticEvent] = (0..<3).map { i in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                ],
                relativeTime: TimeInterval(i) * beatSpacing,
                duration: 0.09
            )
        }

        // Intensity parameter curve that varies by > 0.3 units (Req 8.7).
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0,    value: 0.6),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.12, value: 1.0),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.24, value: 0.7)
            ],
            relativeTime: 0
        )

        play(pattern: makePattern(events: beats, curves: [curve]))
    }

    // MARK: Private Helpers

    private func makePattern(events: [CHHapticEvent],
                              curves: [CHHapticParameterCurve] = []) -> CHHapticPattern? {
        try? CHHapticPattern(events: events, parameterCurves: curves)
    }

    private func play(pattern: CHHapticPattern?) {
        guard let engine, let pattern else { return }
        do {
            // Req 8.5: cancel any in-progress pattern before starting new one.
            try currentPlayer?.cancel()
            currentPlayer = try engine.makePlayer(with: pattern)
            try currentPlayer?.start(atTime: 0)
        } catch {
            // Req 8.6: silent failure.
        }
    }
}
```

#### Scene Phase Observation

```swift
// In ContentView.swift
.onChange(of: scenePhase) { _, newPhase in
    switch newPhase {
    case .active:       HapticEngine.shared.start()
    case .background:   HapticEngine.shared.stop()
    default:            break
    }
}
```
