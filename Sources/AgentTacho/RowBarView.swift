import SwiftUI
import UsageCore

/// The bar under a window row's or budget's first line (spec 025 FR-001 to
/// FR-003, research R7): a full-width track, the fill in the tone's color
/// and, with a pace, a tick where even use would be. It only draws the
/// `RowBar` decided in UsageCore; it has no tooltip (FR-005) and is hidden
/// from accessibility because the row carries the label (FR-006).
struct RowBarView: View {
    let bar: RowBar

    private static let trackHeight: CGFloat = 4
    private static let tickWidth: CGFloat = 1.5
    private static let height: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                    .frame(width: width, height: Self.trackHeight)
                Capsule().fill(bar.tone.color)
                    .frame(width: width * bar.fill, height: Self.trackHeight)
                if let tick = bar.tick {
                    Rectangle().fill(Color.primary)
                        .frame(width: Self.tickWidth, height: Self.height)
                        .offset(x: min(max(width * tick - Self.tickWidth / 2, 0), max(width - Self.tickWidth, 0)))
                }
            }
            .frame(width: width, height: Self.height)
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}

extension RowBarTone {
    /// Neutral in the secondary color, attention orange, over the limit red
    /// (spec 025 FR-003).
    var color: Color {
        switch self {
        case .neutral: Color.secondary
        case .attention: Color.orange
        case .overLimit: Color.red
        }
    }
}
