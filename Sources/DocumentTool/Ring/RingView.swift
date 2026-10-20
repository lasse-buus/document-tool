import AppKit
import SwiftUI

/// The live ring shown while dragging.
struct RingView: View {
    @ObservedObject var state: RingState

    var body: some View {
        RingFace(items: state.items,
                 highlighted: state.highlighted,
                 category: state.category,
                 fileCount: state.fileCount)
            .frame(width: RingGeometry.size, height: RingGeometry.size)
            .scaleEffect(state.appeared ? 1 : 0.88)
            .opacity(state.appeared ? 1 : 0)
    }
}

/// The ring itself, macOS-style: one frosted-glass donut (same material as popovers and menus),
/// monochrome SF Symbols, and the system accent colour on the selected segment.
/// Also used as a static preview on the setup screen.
struct RingFace: View {
    let items: [ActionItem]
    let highlighted: Int?
    let category: FileCategory
    let fileCount: Int

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // All measurements scale from the live ring's size, so the preview is a miniature.
            let k = side / RingGeometry.size
            let outer = RingGeometry.outerRadius * k
            let inner = RingGeometry.innerRadius * k
            let iconRadius = RingGeometry.iconRadius * k
            let count = items.count

            ZStack {
                // Soft drop shadow (the blur view can't cast one itself).
                Donut(inner: inner, outer: outer)
                    .fill(Color.black.opacity(0.22), style: FillStyle(eoFill: true))
                    .blur(radius: 14 * k)
                    .offset(y: 6 * k)

                // Glass.
                VisualEffectBlur(material: .popover)
                    .mask(Donut(inner: inner, outer: outer).fill(style: FillStyle(eoFill: true)))

                // Hairline separators between segments.
                if count > 1 {
                    Separators(count: count, inner: inner, outer: outer)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }

                // Selected segment.
                if let h = highlighted, items.indices.contains(h) {
                    SliceShape(index: h, count: count, inner: inner + 4 * k, outer: outer - 4 * k, gapDegrees: 1.5)
                        .fill(Color.accentColor)
                        .transition(.opacity)
                }

                // Icons.
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SegmentIcon(item: item, selected: index == highlighted, scale: k)
                        .position(iconPosition(index: index, count: count, radius: iconRadius, side: side))
                }

                // Edges.
                Circle()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    .frame(width: outer * 2, height: outer * 2)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                    .frame(width: inner * 2, height: inner * 2)

                // Center: what will happen, on a solid white disc so it's always readable.
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 4 * k, y: 1 * k)
                    .frame(width: (inner - 3 * k) * 2, height: (inner - 3 * k) * 2)
                CenterLabel(items: items, highlighted: highlighted, category: category,
                            fileCount: fileCount, scale: k)
                    .frame(width: (inner - 9 * k) * 2, height: (inner - 9 * k) * 2)
            }
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func iconPosition(index: Int, count: Int, radius: CGFloat, side: CGFloat) -> CGPoint {
        let angle = Double(index) * 2 * .pi / Double(max(count, 1))  // compass angle, 0 = up
        let c = side / 2
        return CGPoint(x: c + radius * CGFloat(sin(angle)), y: c - radius * CGFloat(cos(angle)))
    }
}

private struct SegmentIcon: View {
    let item: ActionItem
    let selected: Bool
    let scale: CGFloat

    var body: some View {
        Group {
            if let icon = item.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24 * scale, height: 24 * scale)
            } else {
                Image(systemName: item.symbol)
                    .font(.system(size: 17 * scale, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.78))
            }
        }
        .frame(width: 44 * scale, height: 44 * scale)
    }
}

private struct CenterLabel: View {
    let items: [ActionItem]
    let highlighted: Int?
    let category: FileCategory
    let fileCount: Int
    let scale: CGFloat

    var body: some View {
        Group {
            if let h = highlighted, items.indices.contains(h) {
                Text(items[h].title)
                    .font(.system(size: 11.5 * scale, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
            } else {
                VStack(spacing: 3 * scale) {
                    Image(systemName: category.symbol)
                        .font(.system(size: 13 * scale, weight: .medium))
                    Text(fileCount > 1 ? "\(fileCount) files" : category.title)
                        .font(.system(size: 10 * scale, weight: .medium))
                }
                .foregroundStyle(Color.black.opacity(0.5))
            }
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.75)
    }
}

// MARK: - Shapes

/// A ring (annulus). Fill with `eoFill` so the middle stays empty.
struct Donut: Shape {
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
        p.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
        return p
    }
}

/// Thin radial lines on the borders between segments.
private struct Separators: Shape {
    let count: Int
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let span = 360 / Double(count)
        var p = Path()
        for i in 0..<count {
            let a = (Double(i) * span + span / 2) * .pi / 180
            let dx = CGFloat(sin(a)), dy = -CGFloat(cos(a))
            p.move(to: CGPoint(x: c.x + (inner + 6) * dx, y: c.y + (inner + 6) * dy))
            p.addLine(to: CGPoint(x: c.x + (outer - 6) * dx, y: c.y + (outer - 6) * dy))
        }
        return p
    }
}

/// A ring segment. Built from points so it doesn't depend on SwiftUI's arc direction rules.
struct SliceShape: Shape {
    let index: Int
    let count: Int
    let inner: CGFloat
    let outer: CGFloat
    var gapDegrees: Double = 3

    func path(in rect: CGRect) -> Path {
        guard count > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let span = 360 / Double(count)
        let mid = Double(index) * span
        let start = mid - span / 2 + gapDegrees / 2
        let end = mid + span / 2 - gapDegrees / 2
        let steps = 48

        func point(_ compassDegrees: Double, _ r: CGFloat) -> CGPoint {
            let a = compassDegrees * .pi / 180
            return CGPoint(x: center.x + r * CGFloat(sin(a)), y: center.y - r * CGFloat(cos(a)))
        }

        var path = Path()
        path.move(to: point(start, outer))
        for s in 1...steps {
            path.addLine(to: point(start + (end - start) * Double(s) / Double(steps), outer))
        }
        for s in stride(from: steps, through: 0, by: -1) {
            path.addLine(to: point(start + (end - start) * Double(s) / Double(steps), inner))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Native blur

/// Real macOS vibrancy (NSVisualEffectView) that blurs whatever is behind the window.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
