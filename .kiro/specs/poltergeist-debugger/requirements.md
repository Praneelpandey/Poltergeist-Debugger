# Requirements Document

## Introduction

Poltergeist Debugger is an iOS 17+ Augmented Reality puzzle game developed as a Kiroween 2026 Costume Contest entry. The game materializes classic computer science bugs as haunting physical entities in the player's real-world environment using RealityKit's Entity-Component-System architecture. Players diagnose and physically manipulate 3D AR entities anchored to a real desk surface to repair a "cursed" virtual motherboard. The experience combines spatial computing, CoreHaptics feedback, and a SwiftUI heads-up display to deliver three distinct debugging puzzles: The Memory Leak, The Race Condition, and The Dangling Pointer.

## Glossary

- **Game**: The Poltergeist Debugger iOS application.
- **GameLoopState**: The `@Observable` view model that bridges RealityKit ECS events to SwiftUI overlays.
- **Motherboard**: The root RealityKit entity anchored to a horizontal surface that serves as the puzzle workspace.
- **CurseStateComponent**: A custom RealityKit component that tracks whether an entity is broken (`isCursed: Bool`, `curseType: CurseType`, `snapRadius: Float`).
- **DraggableComponent**: A custom RealityKit component that flags an entity as player-interactive.
- **CurseResolutionSystem**: A custom per-frame RealityKit system that evaluates proximity between fix entities and cursed entities, triggering resolution when distance thresholds are met.
- **Fix Entity**: A draggable tool entity the player uses to resolve a specific curse (e.g., Deallocator, Mutex Lock).
- **Cursed Entity**: A RealityKit entity bearing a `CurseStateComponent` with `isCursed = true`.
- **Memory Leak Puzzle**: Puzzle 1 — a RAM bank entity overflowing with a green particle mist, resolved by dragging a Deallocator onto it.
- **Race Condition Puzzle**: Puzzle 2 — two gear entities spinning at mismatched velocities, resolved by dropping a Mutex Lock between them.
- **Dangling Pointer Puzzle**: Puzzle 3 — a disconnected ModelEntity drifting aimlessly, resolved by snapping it to the Motherboard tree.
- **Deallocator**: The Fix Entity for the Memory Leak Puzzle.
- **Mutex Lock**: The Fix Entity for the Race Condition Puzzle.
- **HUD**: The SwiftUI heads-up display overlay rendered on top of the RealityView.
- **Snap Zone**: The spatial region around a Cursed Entity within which a dropped Fix Entity triggers curse resolution.
- **LiDAR**: Light Detection And Ranging sensor used by supported iPhones for precise plane detection.
- **ECS**: Entity-Component-System, the architectural pattern used by RealityKit.
- **ARWorldTrackingConfiguration**: The ARKit configuration used for horizontal plane detection and world anchoring.

## Requirements

### Requirement 1: AR Session Initialization and Plane Detection

**User Story:** As a player, I want the app to scan my desk and anchor the motherboard to a flat surface, so that the AR puzzle exists in a stable, real-world location.

#### Acceptance Criteria

1. WHEN the Game launches, THE Game SHALL request camera and motion usage permissions before presenting any AR content.
2. WHEN camera permission is granted, THE Game SHALL initialize an `ARWorldTrackingConfiguration` with horizontal plane detection enabled.
3. WHEN a horizontal plane with an area of at least 0.09 square metres is detected, THE Game SHALL anchor the Motherboard entity to that plane's center.
4. IF multiple horizontal planes are detected simultaneously, THEN THE Game SHALL anchor the Motherboard to the plane with the largest area.
5. WHILE the Game is searching for a suitable plane, THE HUD SHALL display a scanning indicator instructing the player to point the device at a flat surface.
6. IF camera permission is denied, THEN THE Game SHALL display a non-AR fallback screen explaining that camera access is required, with a deep link to iOS Settings.
7. WHEN the Motherboard anchor is established, THE GameLoopState SHALL transition from `scanning` state to `playing` state.
8. IF the ARKit tracking state is interrupted after the Motherboard has been anchored, THEN THE Game SHALL display a recovery indicator on the HUD and attempt to resume the AR session without resetting puzzle progress.

---

### Requirement 2: RealityView and SwiftUI Integration

**User Story:** As a player, I want a responsive heads-up display layered over the AR scene, so that I can track puzzle progress and receive in-game feedback without leaving the AR experience.

#### Acceptance Criteria

1. THE Game SHALL render all AR content exclusively via `RealityView` within a SwiftUI view hierarchy.
2. THE HUD SHALL be implemented as a SwiftUI overlay composited on top of the `RealityView`.
3. THE HUD SHALL apply a custom Metal shader `.layerEffect` that produces a desaturated color grading with a vignette darkening the frame edges and a visible film-grain or noise texture overlaid on all HUD elements.
4. WHEN `GameLoopState` publishes a state change, THE HUD SHALL update within 16 milliseconds of the state change being published.
5. IF `RealityView` is unable to initialize world-tracking due to missing ARKit session support on the current device (such as in the Xcode Simulator), THEN THE Game SHALL remain in 100% `RealityView` and anchor the Motherboard entity using `AnchorEntity(world: .zero)` as a virtual desktop camera anchor, so that all 3D puzzles remain fully testable without any `UIKit` wrapper.

---

### Requirement 3: ECS Component and System Architecture

**User Story:** As a developer, I want all puzzle logic encapsulated in custom RealityKit components and systems, so that puzzle state is decoupled from SwiftUI and independently testable.

#### Acceptance Criteria

1. THE Game SHALL define a `CurseStateComponent` conforming to `RealityKit.Component` with properties `isCursed: Bool` and `curseType: CurseType`, and SHALL also include a `snapRadius: Float` property defaulting to `0.12` metres.
2. THE Game SHALL define a `DraggableComponent` conforming to `RealityKit.Component` that marks an entity as eligible for drag gesture input handling, such that only entities carrying this component respond to drag gestures.
3. THE Game SHALL register and run a `CurseResolutionSystem` conforming to `RealityKit.System` that executes per frame.
4. WHEN the `CurseResolutionSystem` detects that a Fix Entity's world-space position is within the entity's own `snapRadius` value of its target Cursed Entity's origin, THE `CurseResolutionSystem` SHALL set `isCursed = false` on the Cursed Entity's `CurseStateComponent`.
5. WHEN `isCursed` transitions to `false` on a Cursed Entity for the first time in a resolution cycle, THE `CurseResolutionSystem` SHALL post exactly one notification to `GameLoopState` carrying the resolved `curseType`, and SHALL NOT post additional notifications for the same entity on subsequent frames.
6. THE `CurseResolutionSystem` SHALL NOT call any `@MainActor`-isolated method directly from its per-frame `update` function.
7. IF `CurseResolutionSystem` must communicate a state change to `GameLoopState`, THEN THE `CurseResolutionSystem` SHALL dispatch that communication through a thread-safe shared data structure that is read by `GameLoopState` outside the per-frame update loop.

---

### Requirement 4: Spatial Input — Drag and Tap Gestures

**User Story:** As a player, I want to drag fix tools onto cursed entities using natural touch gestures, so that solving puzzles feels physically intuitive.

#### Acceptance Criteria

1. THE Game SHALL use SwiftUI `DragGesture` targeted via `TargetedToEntity()` as the primary mechanism for moving Fix Entities in 3D space.
2. THE Game SHALL use SwiftUI `SpatialTapGesture` targeted via `TargetedToEntity()` for any tap-to-select interactions on AR entities.
3. THE Game SHALL not perform manual raycasting for spatial input except as a documented, strictly necessary fallback.
4. WHEN a player begins dragging a Fix Entity, THE Game SHALL visually highlight the Fix Entity by increasing its brightness by at least 30% above its idle state for the duration of the drag.
5. WHEN a dragged Fix Entity enters a Snap Zone, THE Game SHALL snap the entity to the Snap Zone's anchor position within 0.1 seconds and deliver a haptic snap pulse via `CoreHaptics` within 50 milliseconds of snap completion.
6. WHEN a player releases a Fix Entity outside any Snap Zone, THE Game SHALL animate the entity back to its original resting position over a duration of 0.2 to 0.5 seconds using an ease-out curve.
7. IF a `DragGesture` event is lost mid-drag due to system interruption, THEN THE Game SHALL return the Fix Entity to its original resting position within 0.5 seconds without requiring player input.
8. IF a Fix Entity is dragged to a Snap Zone that is already occupied by another Fix Entity, THEN THE Game SHALL reject the snap, deliver haptic feedback indicating rejection, and return the dragged entity to its original resting position.

---

### Requirement 5: Puzzle 1 — The Memory Leak

**User Story:** As a player, I want to stop the green particle mist overflowing from the RAM bank by dragging a Deallocator onto it, so that I can experience the visceral satisfaction of fixing a memory leak in AR.

#### Acceptance Criteria

1. WHEN the Memory Leak Puzzle begins, THE Game SHALL attach a `ParticleEmitterComponent` to the RAM bank entity emitting green particles at a constant rate without interruption.
2. WHILE the RAM bank entity's `CurseStateComponent` has `isCursed = true`, THE Game SHALL sustain the green particle emission at the same rate established when the puzzle began.
3. WHEN a Deallocator Fix Entity is dropped within the RAM bank entity's configured `snapRadius` of the RAM bank entity's Snap Zone center, THE `CurseResolutionSystem` SHALL set `isCursed = false` on the RAM bank's `CurseStateComponent`.
4. IF a non-Deallocator entity is dropped within the RAM bank entity's Snap Zone, THEN THE `CurseResolutionSystem` SHALL ignore the drop and leave `isCursed` unchanged on the RAM bank's `CurseStateComponent`.
5. IF the Deallocator Fix Entity is released at a distance greater than the RAM bank entity's configured `snapRadius` from the RAM bank entity's Snap Zone center, THEN THE Game SHALL ignore the drop and leave `isCursed` unchanged on the RAM bank's `CurseStateComponent`.
6. WHEN `isCursed` is set to `false` on the RAM bank entity, THE Game SHALL halt the `ParticleEmitterComponent` emission and play a success sound via an `AudioFileResource`.
7. WHEN the Memory Leak Puzzle is resolved, THE GameLoopState SHALL increment the resolved puzzle count by 1 and update the HUD to reflect the new resolved puzzle count.

---

### Requirement 6: Puzzle 2 — The Race Condition

**User Story:** As a player, I want to synchronize two mismatched spinning gears by dropping a Mutex Lock between them, so that I can physically experience resolving a race condition.

#### Acceptance Criteria

1. WHEN the Race Condition Puzzle begins, THE Game SHALL attach `PhysicsMotionComponent` values to two gear entities with angular velocities of 3.0 rad/s and 7.0 rad/s respectively.
2. WHILE the two gear entities have unequal angular velocities, THE Game SHALL render a spark particle emitter on each gear's mesh.
3. WHEN the Mutex Lock Fix Entity is released within the Mutex Lock entity's configured `snapRadius` of the midpoint between the two gear entities, THE `CurseResolutionSystem` SHALL trigger race condition resolution.
4. WHEN race condition resolution is triggered, THE Game SHALL update the `PhysicsMotionComponent` angular velocity of both gear entities to 5.0 rad/s.
5. WHEN race condition resolution is triggered, THE Game SHALL disable the spark `ParticleEmitterComponent` on both gear entities.
6. WHEN the Race Condition Puzzle is resolved, THE `GameLoopState` SHALL increment the resolved puzzle count by 1 and THE Game SHALL update the HUD to display the new resolved puzzle count.

---

### Requirement 7: Puzzle 3 — The Dangling Pointer

**User Story:** As a player, I want to grab a drifting disconnected logic branch and snap it back onto the motherboard, so that I can physically fix a dangling pointer in AR space.

#### Acceptance Criteria

1. WHEN the Dangling Pointer Puzzle begins, THE Game SHALL present a `ModelEntity` in a detached state, not parented to the Motherboard entity, with a continuous drifting transform animation at a translation speed no greater than 0.05 m/s.
2. WHILE the `ModelEntity` is detached from the Motherboard entity tree, THE `ModelEntity`'s `CurseStateComponent` SHALL maintain `isCursed = true`.
3. WHEN a player drags the drifting `ModelEntity` to within the Motherboard's designated anchor point's configured `snapRadius` of the Motherboard's designated anchor point, THE Game SHALL call `setParent()` to attach the `ModelEntity` to the Motherboard entity as a child.
4. WHEN `setParent()` is called to attach the `ModelEntity` to the Motherboard, THE Game SHALL interpolate the `ModelEntity`'s local position to the designated anchor offset within 0.2 seconds.
5. WHEN the `ModelEntity` is successfully parented to the Motherboard, THE `CurseStateComponent` on the `ModelEntity` SHALL be updated to `isCursed = false`.
6. WHEN the Dangling Pointer Puzzle is resolved, THE GameLoopState SHALL increment the resolved puzzle count by 1 and THE HUD SHALL update to display the new resolved puzzle count.
7. IF the player releases the `ModelEntity` at a distance greater than the Motherboard's designated anchor point's configured `snapRadius` from the Motherboard's designated anchor point, THEN THE Game SHALL restore the `ModelEntity` to its detached drifting state with `isCursed = true` unchanged.

---

### Requirement 8: CoreHaptics Feedback

**User Story:** As a player, I want to feel distinct haptic pulses when I snap a fix tool into place or interact with cursed entities, so that the tactile feedback reinforces the physical debugging theme.

#### Acceptance Criteria

1. THE Game SHALL create and maintain a `CHHapticEngine` instance from the start of an active game session until the session ends or the application moves to the background.
2. WHEN a Fix Entity snaps into a Snap Zone, THE Game SHALL trigger a snap haptic pattern with an intensity value in the range 0.7–1.0 and a duration of 0.08–0.12 seconds via `CHHapticEngine`.
3. WHEN the player begins dragging a Fix Entity bearing a `DraggableComponent`, THE Game SHALL trigger a pickup haptic pulse with an intensity value in the range 0.2–0.4 and a duration of 0.05–0.10 seconds.
4. WHEN a puzzle is fully resolved, THE Game SHALL trigger a success haptic pattern consisting of exactly 3 beats, where each beat has an intensity value in the range 0.6–1.0 and adjacent beats are separated by a gap of 0.10–0.15 seconds.
5. IF a haptic event is triggered while another haptic pattern is still playing, THEN THE Game SHALL cancel the in-progress pattern and immediately play the newly triggered pattern.
6. IF the `CHHapticEngine` fails to start or is interrupted, THEN THE Game SHALL continue gameplay silently without haptic feedback and SHALL NOT display an error to the player.
7. WHERE the device supports advanced haptic patterns (Taptic Engine), THE Game SHALL use `CHHapticEvent` parameter curves that vary intensity by at least 0.3 units across the duration of the snap and success patterns.

---

### Requirement 9: Spatial Audio

**User Story:** As a player, I want to hear eerie ambient sounds and positional audio cues emanating from cursed entities, so that the haunted atmosphere is spatially convincing.

#### Acceptance Criteria

1. THE Game SHALL load background ambiance as an `AudioFileResource`, attach it to the Motherboard entity as a looping audio source, and begin playback when the AR session starts so it continuously emanates from the Motherboard's real-world anchor point.
2. WHEN a Cursed Entity is spawned into the AR scene and has not yet been resolved, THE Game SHALL play a looping positional audio cue attached to that entity so the sound source tracks the entity's world position.
3. WHEN a puzzle is resolved, THE Game SHALL play a non-looping resolution sound effect attached to the now-fixed entity and stop that entity's looping positional audio cue.
4. THE Game SHALL configure `RealityKit` spatial audio attenuation with a reference distance of no greater than 0.5 metres and a maximum audible distance of no greater than 5 metres from the Motherboard, so that sounds reach full volume at the reference distance and become inaudible beyond the maximum audible distance.
5. IF an `AudioFileResource` fails to load, THEN THE Game SHALL log the failure and continue without that audio cue, not interrupting gameplay.

---

### Requirement 10: Game Progression and Win Condition

**User Story:** As a player, I want to see my progress across all three puzzles and receive a satisfying conclusion when all bugs are fixed, so that the experience has a clear narrative arc.

#### Acceptance Criteria

1. THE GameLoopState SHALL track the count of resolved puzzles as an integer in the range 0 to 3, incrementing by 1 each time a puzzle transitions to resolved state.
2. THE HUD SHALL display the current resolved puzzle count as a fraction (resolved/3) and the names of all curses whose `isCursed` value is `true` at all times during gameplay.
3. WHEN all three puzzles are resolved, THE Game SHALL transition `GameLoopState` to `victoryState` within 1 second of the third puzzle resolving.
4. WHEN `victoryState` is entered, THE Game SHALL play a haptic sequence of at least 2 distinct pulses followed by a victory audio sting of no longer than 5 seconds in duration.
5. WHEN `victoryState` is entered, THE HUD SHALL display a full-screen victory overlay covering all gameplay elements with the message "All Bugs Exorcised" and a clearly labeled restart option.
6. WHEN the player selects the restart option from the victory overlay, THE Game SHALL reset all `CurseStateComponent` instances to `isCursed = true`, reinitialize all puzzle entities to their starting state, reset the resolved puzzle count to 0, and return `GameLoopState` to its initial pre-victory state without requiring a full app relaunch.
7. IF `GameLoopState` receives a puzzle resolution event when the resolved count is already 3, THEN THE Game SHALL ignore the event and retain the current `victoryState` without modification.
8. IF the victory audio sting asset is unavailable at runtime, THEN THE Game SHALL complete the `victoryState` transition and display the victory overlay without audio, with no error shown to the player.

---

### Requirement 11: Parser and Serializer — Game State Persistence

**User Story:** As a player, I want my puzzle progress to be saved if I background the app, so that I can resume exactly where I left off.

#### Acceptance Criteria

1. WHEN the app transitions to the background, THE Game SHALL serialize the current `GameLoopState` — including resolved puzzle flags and entity transform snapshots — to a JSON representation using `Codable` within 2 seconds of the transition event.
2. WHEN the app returns to the foreground, THE Game SHALL deserialize the saved JSON and restore `GameLoopState` to the persisted values before the first game frame is rendered.
3. THE Game SHALL store the serialized JSON to the app's sandboxed `Documents` directory using a deterministic filename that is fixed per save slot and does not vary between app launches.
4. IF the persisted JSON is malformed or represents a schema version other than the current version, THEN THE Game SHALL discard the file, emit a warning to the system log, and initialize a fresh `GameLoopState` as if no save file existed.
5. FOR ALL valid `GameLoopState` values, serializing then deserializing SHALL produce a `GameLoopState` whose resolved puzzle flags and entity transform snapshots are each equal to those of the original state.
6. THE Game SHALL include an integer schema version field in the serialized JSON, and WHEN the current schema version changes, THE Game SHALL increment this field by 1 so that version mismatches between the saved file and the running app are detectable.
7. IF writing the serialized JSON to the `Documents` directory fails for any reason, THEN THE Game SHALL retain the previous valid save file unchanged and surface an error indication to the player within 3 seconds.
