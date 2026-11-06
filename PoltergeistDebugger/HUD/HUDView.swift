import SwiftUI

// MARK: - HUDView

/// SwiftUI overlay composited on top of the RealityView (Req 2.2).
///
/// Observes GameLoopState directly — because GameLoopState is @Observable,
/// SwiftUI tracks only the specific properties this view reads and redraws
/// only when those properties change (within the 16 ms budget of Req 2.4).
///
/// ## Layout
/// - Top bar: resolved puzzle count as a fraction (e.g. "1 / 3") (Req 10.2).
/// - Below that: names of all remaining active curses (Req 10.2).
/// - Scanning overlay: shown when sessionPhase == .scanning (Req 1.5).
/// - Tracking-interrupted banner: shown when AR tracking is lost (Req 1.8).
/// - Victory overlay: shown when sessionPhase == .victory (Req 10.5).
///
/// The Metal shader (.layerEffect) is applied to this view in Task 16.2 (Phase 4).
/// For Phase 1 the view renders without the shader so it can be previewed and
/// tested independently.
struct HUDView: View {

    @State var gameLoopState: GameLoopState

    /// True while ARKit tracking is interrupted (set/cleared by ContentView).
    var isTrackingInterrupted: Bool

    var body: some View {
        ZStack {
            // Scanning overlay — full screen, shown before plane is found.
            if gameLoopState.sessionPhase == .scanning {
                ScanningView()
            }

            // Tracking-interrupted recovery banner (Req 1.8).
            if isTrackingInterrupted {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Tracking lost — move slowly")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(.top, 56)
            }

            // Progress bar — visible during play and victory.
            if gameLoopState.sessionPhase != .scanning {
                VStack {
                    progressBar
                        .padding(.top, 56)
                        .padding(.horizontal, 20)
                    Spacer()
                }
            }

            // Victory overlay — full screen, shown after all puzzles solved.
            if gameLoopState.sessionPhase == .victory {
                VictoryOverlayView(gameLoopState: gameLoopState)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            // "2 / 3 Bugs Exorcised"
            Text("\(gameLoopState.resolvedCount) / 3 Bugs Exorcised")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            // Remaining curse names
            if !gameLoopState.activeCurses.isEmpty {
                HStack(spacing: 6) {
                    ForEach(gameLoopState.activeCurses, id: \.self) { curse in
                        cursePill(for: curse)
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func cursePill(for curse: CurseType) -> some View {
        Text(curse.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(curse.pillColor.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(curse.pillColor.opacity(0.6), lineWidth: 0.5))
    }
}

// MARK: - CurseType display helpers

private extension CurseType {
    var displayName: String {
        switch self {
        case .memoryLeak:      return "Memory Leak"
        case .raceCondition:   return "Race Condition"
        case .danglingPointer: return "Dangling Pointer"
        }
    }

    var pillColor: Color {
        switch self {
        case .memoryLeak:      return .green
        case .raceCondition:   return .yellow
        case .danglingPointer: return .purple
        }
    }
}

#Preview {
    let state = GameLoopState()
    return HUDView(gameLoopState: state, isTrackingInterrupted: false)
        .background(Color.black)
}
