---
inclusion: auto
name: swift-realitykit-conventions
description: Swift 6 strict concurrency rules, RealityKit ECS separation-of-concerns rules, and build environment guidance. Activate whenever writing Swift source files for the Poltergeist Debugger iOS RealityKit project.
---

# Swift & RealityKit Conventions — Poltergeist Debugger

## 1. Build Environment

- **Do not run `xcodebuild`, `swift build`, or any Xcode CLI tool.**  
  This workspace is on a Windows machine. All Swift source files are written as pure text and built only when opened in Xcode on macOS. Do not attempt to compile, link, or simulate the app locally.
- When verifying correctness, reason about the code statically (type signatures, API contracts, control flow). Do not emit shell commands that invoke Apple toolchains.
- File paths use the Xcode project convention (`PoltergeistDebugger/<Group>/<File>.swift`). Create files at the matching relative path inside the workspace root.

---

## 2. Swift 6 Strict Concurrency

### 2.1 Sendability
- Every type that crosses actor boundaries **must** conform to `Sendable` or be `@unchecked Sendable` with an explicit lock comment.
- Value types (`struct`, `enum`) used in ECS components must be `Sendable` by default — add explicit conformance only when the compiler cannot infer it.
- Never silence a `Sendable` warning with `@preconcurrency` without a written justification comment.

### 2.2 Actor isolation
- `GameLoopState` is `@MainActor`. Do **not** call its methods directly from `RealityKit.System.update(context:)` — that closure runs off the main actor.
- Route all ECS → SwiftUI communication through `CurseEventBuffer` (NSLock-protected) and drain it inside the `RealityView update:` closure, which is already on `@MainActor`.
- Mark any helper that must run on the main thread with `@MainActor` explicitly rather than relying on implicit isolation.
- When a `Task { }` is created inside a `@MainActor` context, it inherits main-actor isolation unless explicitly hopped with `Task.detached`.

### 2.3 Async / await
- Prefer `async`/`await` over completion handlers for new code (persistence, permission requests).
- Never call `async` functions with `.wait()` or `DispatchSemaphore` — this deadlocks the main run loop on iOS.
- Use `Task { @MainActor in … }` to bridge back to the main actor from a detached context.

### 2.4 Data races
- `CurseEventBuffer` uses `NSLock` and is marked `@unchecked Sendable`. Any mutation of its internal array must be inside `lock.withLock { }`.
- Do **not** add `@Published` or `@State` storage to types that are accessed from background threads.

---

## 3. RealityKit ECS Separation of Concerns

### 3.1 Components are pure data
- `CurseStateComponent` and `DraggableComponent` must contain **only stored properties** — no methods with side effects, no references to `GameLoopState`, no `UIKit`/`SwiftUI` imports.
- Components must conform to `RealityKit.Component`. When `Codable` is also required (for persistence), ensure all stored properties are `Codable`-compatible (`SIMD3<Float>` is not `Codable` by default — use scalar fields or a custom implementation).

### 3.2 Systems own per-frame logic
- All per-frame evaluation (proximity checks, state mutations, event posting) lives in `CurseResolutionSystem.update(context:)` and `DragReturnSystem.update(context:)`.
- Systems must **not** import `SwiftUI` or reference any `@Observable` object directly.
- Systems communicate outward only via `CurseEventBuffer.shared.post(_:)`.
- Never call `System.registerSystem()` inside `System.init(scene:)` — register all components and systems once in `PoltergeistDebuggerApp.init()`.

### 3.3 Entity queries
- Declare `EntityQuery` as `private static let` on the system class. Constructing a query per frame is wasteful and triggers repeated allocations.
- Use `context.entities(matching:updatingSystemWhen:)` — pass `.rendering` for systems that modify transforms or visual state each frame.

### 3.4 Gesture hit-testing prerequisites
- Any entity that must receive `DragGesture().targetedToAnyEntity()` or `SpatialTapGesture().targetedToAnyEntity()` **must** have both:
  - `InputTargetComponent()` — marks the entity as interactive
  - `CollisionComponent(shapes: […])` — provides the hit-test geometry
- Attaching only `DraggableComponent` is not sufficient; without these two components RealityKit silently ignores the entity.

### 3.5 Physics
- Attach `PhysicsBodyComponent(mode: .kinematic)` to any entity that uses `PhysicsMotionComponent`. Without a physics body, RealityKit evaluates but does not apply the motion component to the entity's transform.
- Do not use `PhysicsBodyComponent(mode: .dynamic)` for puzzle entities — dynamic bodies respond to gravity and collisions in ways that conflict with designed puzzle behaviour.

### 3.6 Entity parenting
- When calling `setParent(_:preservingWorldTransform:)`, always pass `preservingWorldTransform: true` unless you explicitly intend the child to jump to a local-space offset.
- After `setParent`, reset `localTransform` to the designated anchor offset in the same frame to avoid one-frame visual pop.

### 3.7 Simulator fallback
- Use `ARWorldTrackingConfiguration.isSupported` (a runtime Bool) as the single branch point between device AR and the Simulator fallback (`AnchorEntity(world: .zero)`).
- Do **not** use `#if targetEnvironment(simulator)` — it creates two separate code paths that diverge silently. The runtime check keeps a single unified code path.

---

## 4. SwiftUI + RealityView Rules

- All AR content is rendered inside `RealityView`. Do **not** wrap `ARView` in `UIViewRepresentable` for any purpose except a documented, unavoidable world-tracking fallback (and even then, keep all gesture and HUD code in SwiftUI).
- Gesture modifiers (`.gesture(DragGesture().targetedToAnyEntity())`) must be applied to the `RealityView` directly, not to a parent container.
- The `RealityView update:` closure runs on `@MainActor` and fires every frame — keep it lightweight. Drain `CurseEventBuffer` here; do not do file I/O or expensive allocations.
- Do **not** call `@Observable` properties from inside the `RealityView make:` closure's background task; post to `GameLoopState` only from the `update:` closure or a `Task { @MainActor in }`.

---

## 5. Metal Shader Rules

- HUD shaders live in `HUD/Shaders/PoltergeistHUD.metal`. Include `<SwiftUI/SwiftUI.h>` and `<metal_stdlib>`.
- Shaders used with `.layerEffect` must be declared `[[stitchable]]`. The function signature must match: `half4 name(float2 position, SwiftUI::Layer layer, …user args…)`.
- Pass `maxSampleOffset: .zero` when the shader only reads the pixel at the current position (no blur, no displacement). Incorrect `maxSampleOffset` causes SwiftUI to over-rasterize.
- Keep grain animation deterministic given the same `time` value — use pure math (`fract`, `sin`, `dot`), not Metal random functions, so the shader is testable.

---

## 6. File Naming & Organisation

| Layer | Folder | Naming rule |
|---|---|---|
| App entry | `PoltergeistDebugger/` | `PoltergeistDebuggerApp.swift` |
| ECS components | `ECS/Components/` | `<ComponentName>.swift` |
| ECS systems | `ECS/Systems/` | `<SystemName>.swift` |
| Puzzle helpers | `Puzzles/` | `<PuzzleName>Puzzle.swift`, `PuzzleFactory.swift` |
| SwiftUI views | `HUD/` | `HUDView.swift`, `ScanningView.swift`, `VictoryOverlayView.swift` |
| Metal shaders | `HUD/Shaders/` | `PoltergeistHUD.metal` |
| Observable state | `State/` | `GameLoopState.swift`, `CurseEventBuffer.swift`, `SessionPhase.swift` |
| AR session | `AR/` | `ARSessionCoordinator.swift`, `SimulatorFallback.swift` |
| Persistence | `Persistence/` | `GameStatePersistence.swift`, `PersistedGameState.swift`, `EntityTransformSnapshot.swift` |
| Audio | `Audio/` | `SpatialAudioCoordinator.swift` |
| Haptics | `Haptics/` | `HapticEngine.swift` |
| Tests | `Tests/PoltergeistDebuggerTests/` | `<AreaUnderTest>Tests.swift` |

