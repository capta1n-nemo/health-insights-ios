import SwiftUI

/// A circular 0–100 score dial, à la the Apple activity rings / Oura readiness
/// score. Colour tracks the value.
struct ScoreDial: View {
    let score: Double            // 0…100
    var label: String = ""
    var size: CGFloat = 120

    private var fraction: Double { max(0, min(1, score / 100)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.color(forScore: score),
                        style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: fraction)
            VStack(spacing: 2) {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                if !label.isEmpty {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) score \(Int(score.rounded())) out of 100")
    }
}

/// A compact sparkline for trend previews on cards, built with Swift Charts.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let minV = values.min(), let maxV = values.max() {
                let range = max(maxV - minV, 0.0001)
                Path { path in
                    for (i, v) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((v - minV) / range))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            } else {
                Rectangle().fill(Color.secondary.opacity(0.1))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: 32)
    }
}
