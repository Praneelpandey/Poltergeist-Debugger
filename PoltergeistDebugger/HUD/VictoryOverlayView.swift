import SwiftUI

// MARK: - VictoryOverlayView

/// Full-screen overlay shown when GameLoopState.sessionPhase == .victory (Req 10.5).
///
/// ## Requirements satisfied
/// - Covers all gameplay elements (ZStack with .ignoresSafeArea on parent).
/// - Displays the exact message "All Bugs Exorcised" (Req 10.5).
/// - Provides a clearly labelled restart button (Req 10.5).
/// - Restart calls gameLoopState.restartSession() which resets resolvedCount,
///   activeCurses, and sessionPhase without a full app relaunch (Req 10.6).
/// - Phase 4 (Task 17.1) adds victory haptic + audio sting to this view.
struct VictoryOverlayView: View {

    @State var gameLoopState: GameLoopState

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 28) {

                // Trophy icon
                Image(systemName: "cpu.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .green.opacity(0.6), radius: 20)

                // Required message (Req 10.5)
                Text("All Bugs Exorcised")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("The motherboard is clean.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))

                // Restart button (Req 10.5, 10.6)
                Button {
                    gameLoopState.restartSession()
                } label: {
                    Label("Debug Again", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(40)
        }
    }
}

#Preview {
    let state = GameLoopState()
    return VictoryOverlayView(gameLoopState: state)
}
