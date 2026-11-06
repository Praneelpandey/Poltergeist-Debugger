import SwiftUI

// MARK: - ScanningView

/// Displayed over the RealityView while GameLoopState.sessionPhase == .scanning.
///
/// Instructs the player to point the device at a flat horizontal surface so
/// ARKit can detect a plane ≥ 0.09 m² (Req 1.5).
///
/// Dismissed automatically when sessionPhase transitions to .playing —
/// ContentView conditionally overlays this view based on sessionPhase.
struct ScanningView: View {

    var body: some View {
        VStack(spacing: 16) {
            // Animated scanning ring
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 72))
                .foregroundStyle(.white.opacity(0.85))
                .symbolEffect(.pulse)

            Text("Point at a flat surface")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Move your device slowly over a desk or table")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    ZStack {
        Color.black
        ScanningView()
    }
}
