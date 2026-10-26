import SwiftUI

// Движение: новые модификаторы и экраны проверяются вместе с темой оформления
// PROBE_WITH="Utils/NPMotion.swift Views/Components/NPPulseViews.swift Utils/NetPulseTheme.swift"
struct ProbeMotion: View {
    var body: some View {
        VStack(spacing: 12) {
            NetworkPulseLine(color: .green, intensity: 0.5, isFlat: false, isBusy: true)
                .frame(height: 44)
            NetworkPulseLine(color: .red, intensity: 0, isFlat: true)
            Text("42.0")
                .contentTransition(.numericText())
                .npBreathingGlow(color: .blue, active: true)
                .npAppear()
                .npBounce(value: 1)
                .npAnimation(value: 2)
            NPRecordingDot(color: .red)
            Circle().stroke(Color.blue)
                .phaseAnimator([0.0, 1.0]) { view, progress in
                    view.scaleEffect(1 + 1.6 * progress).opacity(0.7 * (1 - progress))
                } animation: { progress in
                    progress == 1.0 ? .easeOut(duration: 1.8) : nil
                }
            NPIntroOverlay()
        }
        .npMotionPolicy()
    }
}

let probeShape = ECGShape(cycles: 2, phase: 0.1, amplitude: 0.5, drawn: 0.7)
