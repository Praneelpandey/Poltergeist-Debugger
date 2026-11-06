# Poltergeist Debugger

> **Kiroween 2026 — Costume Contest entry**

A spatial computing puzzle game where classic computer science bugs materialise as haunted physical entities in Augmented Reality. Diagnose and physically manipulate 3D objects anchored to your real desk to repair a cursed virtual motherboard.

---

## Track

**Costume Contest** — _Kiroween 2026_

This submission dresses a set of abstract software engineering concepts in a horror costume: a Memory Leak becomes a green particle mist overflowing a RAM bank; a Race Condition becomes two grinding gears throwing sparks; a Dangling Pointer becomes a severed logic branch drifting through mid-air. The player fixes each bug by physically interacting with the AR scene using touch gestures.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Platform | iOS 17+ · iPhone 12 or later (A14 Bionic · LiDAR optional) |
| UI framework | SwiftUI — 100%, no UIKit |
| AR / 3D | RealityKit (Entity-Component-System) · ARKit plane detection |
| Gestures | `DragGesture().targetedToAnyEntity()` · `SpatialTapGesture` |
| Haptics | CoreHaptics (`CHHapticEngine`) |
| Audio | RealityKit spatial `AudioFileResource` |
| State | `@Observable` (`GameLoopState`) |
| Persistence | Swift `actor` + `Codable` JSON |
| HUD effects | Metal `.layerEffect` shader (desaturation · vignette · film grain) |
| Development | Spec-driven with [Kiro](https://kiro.dev) — requirements → design → tasks |

---

## Puzzles

### 🟢 Puzzle 1 — The Memory Leak _(implemented)_

A RAM bank entity leaks green particle mist into your room.

**What you see:** A `ParticleEmitterComponent` fills the air around the RAM chip with a continuous green fog.

**How to fix it:** Drag the glowing **Deallocator** tool (a red sphere) onto the RAM bank. When it crosses the entity's snap radius, `CurseResolutionSystem` detects the proximity, sets `isCursed = false`, halts the particle emitter, and plays a satisfying resolution sound.

**Under the hood:**
- `CurseStateComponent` on the RAM bank holds `curseType: .memoryLeak` and `snapRadius: 0.12`
- `DraggableComponent` + `InputTargetComponent` + `CollisionComponent` on the Deallocator enable gesture hit-testing
- `CurseResolutionSystem.update(context:)` runs every frame, measures world-space distance, and posts a `CurseResolvedEvent` to `CurseEventBuffer` (NSLock-protected) when the threshold is crossed
- `GameLoopState.processEvents()` drains the buffer on `@MainActor` and increments `resolvedCount`

### 🟡 Puzzle 2 — The Race Condition _(Phase 3)_

Two gear entities spin at mismatched angular velocities (3.0 rad/s and 7.0 rad/s), throwing sparks. Drop the **Mutex Lock** between them to sync both to 5.0 rad/s and silence the sparks.

### 🟣 Puzzle 3 — The Dangling Pointer _(Phase 3)_

A disconnected logic branch drifts through the air, detached from the Motherboard entity tree. Grab it and snap it back to its anchor point — `setParent()` reattaches it and the drifting animation stops.

---

## Architecture

```
PoltergeistDebugger/
├── ECS/
│   ├── Components/        CurseStateComponent · DraggableComponent
│   └── Systems/           CurseResolutionSystem · DragReturnSystem
├── State/                 GameLoopState (@Observable) · CurseEventBuffer (NSLock)
├── AR/                    ARSessionCoordinator · SimulatorFallback
├── HUD/                   HUDView · ScanningView · VictoryOverlayView
│   └── Shaders/           PoltergeistHUD.metal
├── Puzzles/               PuzzleFactory · MemoryLeakPuzzle · …
├── Persistence/           GameStatePersistence (actor) · PersistedGameState
├── Audio/                 SpatialAudioCoordinator
└── Haptics/               HapticEngine
```

The core design rule: **ECS systems own all per-frame logic; SwiftUI owns all rendering and gesture dispatch; `GameLoopState` is the only bridge between them.** Systems never import SwiftUI; views never query the ECS directly.

---

## Spec-Driven Development

This project was built using [Kiro](https://kiro.dev)'s spec workflow. The full specification lives in `.kiro/specs/poltergeist-debugger/`:

| Document | Purpose |
|---|---|
| [`requirements.md`](.kiro/specs/poltergeist-debugger/requirements.md) | 11 requirements with EARS-format acceptance criteria |
| [`design.md`](.kiro/specs/poltergeist-debugger/design.md) | Architecture, exact Swift signatures, Metal shader, PBT properties |
| [`tasks.md`](.kiro/specs/poltergeist-debugger/tasks.md) | Phased implementation plan with 19 tasks and dependency graph |

Architectural conventions (Swift 6 concurrency, RealityKit ECS rules, build environment guidance) are captured in [`.kiro/steering/swift_realitykit_conventions.md`](.kiro/steering/swift_realitykit_conventions.md) and automatically loaded by Kiro during every code-generation session.

---

## Running the Project

1. Open `PoltergeistDebugger.xcodeproj` in Xcode 16+ on macOS.
2. Select an iPhone 12 or later as the run destination (or the iOS Simulator for the world-origin fallback).
3. Build and run (`⌘R`). On a real device, point the camera at a flat desk — the scanning overlay guides you until a horizontal plane ≥ 0.09 m² is detected.
4. Drag the Deallocator onto the RAM bank to resolve the first puzzle.

> **Simulator note:** `ARWorldTrackingConfiguration.isSupported` returns `false` in the Simulator. The app automatically falls back to `AnchorEntity(world: .zero)`, placing the Motherboard at the world origin so all puzzles are fully playable without a device.

---

## License

MIT — see [LICENSE](LICENSE).  
Copyright © 2026 Praneel Pandey.
