import SwiftUI
import RealityKit

// MARK: - PoltergeistDebuggerApp

/// @main entry point.
///
/// ## ECS Registration (RKFix 4)
/// All custom RealityKit components and systems are registered here — once,
/// before any RealityView is instantiated — rather than inside System.init(scene:).
///
/// Calling registerSystem() inside init(scene:) creates a recursive cycle
/// because RealityKit constructs the system *as part of* registration; the
/// App.init() call site breaks that cycle (Steering §3.2, Task 1.1).
@main
struct PoltergeistDebuggerApp: App {

    init() {
        // Component registration must precede system registration so that
        // EntityQuery expressions referencing these components are valid
        // at system-registration time.
        CurseStateComponent.registerComponent()
        DraggableComponent.registerComponent()

        // System registration. Both stubs are replaced by full implementations
        // in Tasks 6.1 and 6.3 (Phase 2) without changing these call sites.
        CurseResolutionSystem.registerSystem()
        DragReturnSystem.registerSystem()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
