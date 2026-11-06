import SwiftUI

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case bars, wave, rings, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bars: "Bars"
        case .wave: "Wave"
        case .rings: "Rings"
        case .off: "Off"
        }
    }
    /// Bars and Off are free; the others come with Pro.
    var isPro: Bool { self == .wave || self == .rings }
}

/// Shown in place of video for radio and other audio-only streams.
/// HLS streams don't expose their audio samples to apps, so the motion follows play/pause instead of the real waveform.
struct AudioVisualizer: View {
    let style: VisualizerStyle
    let isPlaying: Bool
    let title: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.2), .black], startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { gc, size in
                    switch style {
                    case .bars: drawBars(gc, size, t)
                    case .wave: drawWave(gc, size, t)
                    case .rings: drawRings(gc, size, t)
                    case .off: break
                    }
                }
            }
            VStack(spacing: 6) {
                Image(systemName: "music.note").font(.title2.weight(.semibold))
                Text(title).font(.headline).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.black.opacity(0.35), in: Capsule())
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 12)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var accent: Color { Theme.accent }

    private func level(_ i: Int, _ t: Double) -> Double {
        let f1 = 1.3 + Double((i * 7919) % 13) / 6
        let f2 = 0.7 + Double((i * 104729) % 11) / 9
        let v = 0.5 + 0.3 * sin(t * f1 + Double(i)) + 0.2 * sin(t * f2 * 2.1 + Double(i) * 0.7)
        return isPlaying ? max(0.06, min(1, v)) : 0.06
    }

    private func drawBars(_ gc: GraphicsContext, _ size: CGSize, _ t: Double) {
        let count = 28
        let gap: CGFloat = 4
        let w = (size.width - gap * CGFloat(count + 1)) / CGFloat(count)
        let maxH = size.height * 0.62
        for i in 0..<count {
            let h = maxH * level(i, t)
            let rect = CGRect(x: gap + CGFloat(i) * (w + gap), y: size.height - 16 - h, width: w, height: h)
            gc.fill(Path(roundedRect: rect, cornerRadius: w / 2),
                    with: .linearGradient(Gradient(colors: [accent, accent.opacity(0.35)]),
                                          startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        }
    }

    private func drawWave(_ gc: GraphicsContext, _ size: CGSize, _ t: Double) {
        let mid = size.height * 0.58
        for layer in 0..<3 {
            var path = Path()
            let amp = size.height * (0.16 - Double(layer) * 0.04) * (isPlaying ? 1 : 0.1)
            let speed = 1.6 + Double(layer) * 0.6
            for x in stride(from: 0, through: size.width, by: 3) {
                let p = Double(x / size.width)
                let y = mid + amp * sin(p * 2 * .pi * (1.5 + Double(layer) * 0.5) + t * speed) * sin(p * .pi)
                if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            gc.stroke(path, with: .color(accent.opacity(1 - Double(layer) * 0.3)), lineWidth: 3 - CGFloat(layer) * 0.7)
        }
    }

    private func drawRings(_ gc: GraphicsContext, _ size: CGSize, _ t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.58)
        let base = min(size.width, size.height) * 0.12
        for i in 0..<5 {
            let phase = (t * 0.6 + Double(i) / 5).truncatingRemainder(dividingBy: 1)
            let r = base + (min(size.width, size.height) * 0.4) * (isPlaying ? phase : 0.1 * Double(i) / 5)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            gc.stroke(Path(ellipseIn: rect), with: .color(accent.opacity(isPlaying ? 1 - phase : 0.3)), lineWidth: 3)
        }
        let pulse = base * (0.8 + 0.25 * level(0, t))
        gc.fill(Path(ellipseIn: CGRect(x: center.x - pulse, y: center.y - pulse, width: pulse * 2, height: pulse * 2)), with: .color(accent))
    }
}
